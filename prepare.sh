#!/bin/bash

## Do I have a GPU
GPUS=$(lspci | awk '/NVIDIA/ && /3D controller/' | wc -l)
if [ $? -ne 0 ] || [ $GPUS -eq 0 ]
then
        echo "No NVIDIA GPU detected. Exiting".
        exit 1
fi

## Do I have an additional disk?

ADDL_DISK=$(lsblk | awk  '/^sdc/ {print $1}')
ADDL_PART=$(lsblk -l | awk -v DISK="$ADDL_DISK" '($0 ~ DISK) && ($0 ~ /part/) {print $1}')

if [ -n $ADDL_DISK ] && [ -z $ADDL_PART] 
then
    echo "Found $ADDL_DISK, preparing it for use"
    echo -e "g\nn\np\n1\n\n\nw\n" | sudo fdisk /dev/$ADDL_DISK
    ADDL_DEVICE=$(echo "/dev/"$ADDL_DISK"1")
    sudo mkfs.ext4 $ADDL_DEVICE
    sudo mkdir -p /var/lib/docker
    echo "$ADDL_DEVICE   /var/lib/docker   auto    rw,user,auto    0    0" | sudo tee -a /etc/fstab
    mount /var/lib/docker
    if [ $? -ne 0 ]
    then
        echo "Error during preparing of additional disk. Exiting."
        exit 1
    fi
elif  [ -n $ADDL_DISK ] && [ -n $ADDL_PART] 
then
    echo "Found $ADDL_DISK - $ADDL_PART already mounted, taking no action."

else
    echo "Did not find $ADDL_DISK, taking no action."
fi

## Adding Nvidia Drivers
sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
sudo bash -c 'echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64 /" > /etc/apt/sources.list.d/cuda.list'
sudo bash -c 'echo "deb http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1804/x86_64 /" > /etc/apt/sources.list.d/cuda_learn.list'
sudo bash -c 'apt update && apt install -y nvidia-driver-440 cuda-minimal-build-10-2 -o Dpkg::Options::="--force-overwrite"'

## Adding AWSCli and JQ
sudo apt-get install -y awscli jq

## Installing Docker
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) \
stable"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) \
stable"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-docker2 nvidia-container-toolkit nvidia-container-runtime
jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' /etc/docker/daemon.json | sudo tee /etc/docker/daemon.json
sudo systemctl enable docker
sudo systemctl restart docker

## Ensure user can run docker
sudo usermod -a -G docker $(id -un)

## Installing Docker Compose
sudo curl -L https://github.com/docker/compose/releases/download/1.25.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

## Reboot to load driver
sudo reboot
