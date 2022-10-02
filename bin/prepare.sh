#!/bin/bash

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

## Patch system
sudo apt-get update && sudo apt-mark hold grub-pc && sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o \
                        DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" -qq --force-yes upgrade && \
                        sudo apt-get install --no-install-recommends -y jq
source $DIR/detect.sh
echo "Detected cloud type ${CLOUD_NAME}"

## Do I have a GPU
GPUS=$(lspci | awk '/NVIDIA/ && ( /VGA/ || /3D controller/ ) ' | wc -l )
if [ $? -ne 0 ] || [ $GPUS -eq 0 ];
then
	ARCH="cpu"
        echo "No NVIDIA GPU detected. Will not install drivers."
else
	ARCH="gpu"
fi

## Do I have an additional disk for Docker images - looking for /dev/sdc (Azure)

if [[ "${CLOUD_NAME}" == "azure" ]];
then
    ADDL_DISK=$(lsblk | awk  '/^sdc/ {print $1}')
    ADDL_PART=$(lsblk -l | awk -v DISK="$ADDL_DISK" '($0 ~ DISK) && ($0 ~ /part/) {print $1}')

    if [ -n "$ADDL_DISK" ] && [ -z "$ADDL_PART" ];
    then
        echo "Found $ADDL_DISK, preparing it for use"
        echo -e "g\nn\np\n1\n\n\nw\n" | sudo fdisk /dev/$ADDL_DISK
        sleep 1s
        ADDL_DEVICE=$(echo "/dev/"$ADDL_DISK"1")
        sudo mkfs.ext4 $ADDL_DEVICE
        sudo mkdir -p /var/lib/docker
        echo "$ADDL_DEVICE   /var/lib/docker   ext4    rw,user,auto    0    0" | sudo tee -a /etc/fstab
        mount /var/lib/docker
        if [ $? -ne 0 ]
        then
            echo "Error during preparing of additional disk. Exiting."
            exit 1
        fi
    elif  [ -n "$ADDL_DISK" ] && [ -n "$ADDL_PART" ];
    then
        echo "Found $ADDL_DISK - $ADDL_PART already mounted. Installing into present drive/directory structure."

    else
        echo "Did not find $ADDL_DISK. Installing into present drive/directory structure."
    fi
fi

## Adding Nvidia Drivers
if [[ "${ARCH}" == "gpu" ]];
then
	distribution=$(. /etc/os-release;echo $ID$VERSION_ID | sed 's/\.//')
	sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/3bf863cc.pub
    sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/machine-learning/repos/$distribution/x86_64/7fa2af80.pub
	echo "deb http://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64 /" | sudo tee /etc/apt/sources.list.d/cuda.list
	echo "deb http://developer.download.nvidia.com/compute/machine-learning/repos/$distribution/x86_64 /" | sudo tee /etc/apt/sources.list.d/cuda_learn.list
	sudo apt update && sudo apt install -y nvidia-driver-470-server cuda-minimal-build-11-4 --no-install-recommends -o Dpkg::Options::="--force-overwrite"
fi

## Adding AWSCli
sudo apt-get install -y --no-install-recommends awscli python3-boto3

## Installing Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update && sudo apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

if [[ "${ARCH}" == "gpu" ]];
then
	distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
	curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
	curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

	sudo apt-get update && sudo apt-get install -y --no-install-recommends nvidia-docker2 nvidia-container-toolkit nvidia-container-runtime
    if [ -f "/etc/docker/daemon.json" ];
    then
        echo "Altering /etc/docker/daemon.json with default-rutime nvidia."
        cat /etc/docker/daemon.json | jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' | sudo tee /etc/docker/daemon.json
    else
        echo "Creating /etc/docker/daemon.json with default-rutime nvidia."    
        sudo cp $DIR/../defaults/docker-daemon.json /etc/docker/daemon.json
    fi
fi
sudo systemctl enable docker
sudo systemctl restart docker

## Ensure user can run docker
sudo usermod -a -G docker $(id -un)

## Installing Docker Compose
sudo curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

## Reboot to load driver -- continue install if in cloud-init
CLOUD_INIT=$(pstree -s $BASHPID | awk /cloud-init/ | wc -l)

if [[ "$CLOUD_INIT" -ne 0 ]];
then
    echo "Rebooting in 5 seconds. Will continue with install."
    cd $DIR
    ./runonce.sh "./init.sh -c ${CLOUD_NAME} -a ${ARCH}"
    sleep 5s
    sudo reboot
else
    echo "First stage done. Please reboot and run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
fi
