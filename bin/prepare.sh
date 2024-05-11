#!/usr/bin/env bash

set -e

trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

export DEBIAN_FRONTEND=noninteractive
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

## Check distribution
distribution=$(
    . /etc/os-release
    echo $ID$VERSION_ID | sed 's/\.//'
)

## Check if WSL2
if grep -qi Microsoft /proc/version && grep -q "WSL2" /proc/version; then
    IS_WSL2="yes"
fi

## Remove needsreboot in Ubuntu 22.04
if [[ "${distribution}" == "ubuntu2204" && -z "${IS_WSL2}" ]]; then
    sudo apt remove -y needrestart
fi

## Patch system
sudo apt update && sudo apt-mark hold grub-pc && sudo apt -y -o \
    DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" -qq --force-yes upgrade &&
    sudo apt install --no-install-recommends -y jq awscli python3-boto3
source $DIR/detect.sh
echo "Detected cloud type ${CLOUD_NAME}"

## Do I have a GPU
GPUS=0
if [[ -z "${IS_WSL2}" ]]; then
    GPUS=$(lspci | awk '/NVIDIA/ && ( /VGA/ || /3D controller/ ) ' | wc -l)
else
    if [[ -f /usr/lib/wsl/lib/nvidia-smi ]]; then
        GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
    fi
fi
if [ $? -ne 0 ] || [ $GPUS -eq 0 ]; then
    ARCH="cpu"
    echo "No NVIDIA GPU detected. Will not install drivers."
else
    ARCH="gpu"
fi

## Adding Nvidia Drivers
if [[ "${ARCH}" == "gpu" && -z "${IS_WSL2}" ]]; then
    case $distribution in
    ubuntu2004)
        sudo apt install -y nvidia-driver-525-server --no-install-recommends -o Dpkg::Options::="--force-overwrite"
        ;;
    ubuntu2204)
        sudo apt install -y nvidia-driver-550 --no-install-recommends -o Dpkg::Options::="--force-overwrite"
        ;;
    *)
        echo "Unsupported distribution: $distribution"
        exit 1
        ;;
    esac
fi

## Installing Docker
sudo apt install -y --no-install-recommends docker.io docker-buildx docker-compose-v2

## Install Nvidia Docker Container
if [[ "${ARCH}" == "gpu" ]]; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt update && sudo apt install -y --no-install-recommends nvidia-docker2 nvidia-container-runtime
    if [ -f "/etc/docker/daemon.json" ]; then
        echo "Altering /etc/docker/daemon.json with default-rutime nvidia."
        cat /etc/docker/daemon.json | jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' | sudo tee /etc/docker/daemon.json
    else
        echo "Creating /etc/docker/daemon.json with default-rutime nvidia."
        sudo cp $DIR/../defaults/docker-daemon.json /etc/docker/daemon.json
    fi
fi

## Enable and start docker
if [[ -n "${IS_WSL2}" ]]; then
    sudo service docker restart
else
    sudo systemctl enable docker
    sudo systemctl restart docker
fi

## Ensure user can run docker
sudo usermod -a -G docker $(id -un)

## Reboot to load driver -- continue install if in cloud-init
CLOUD_INIT=$(pstree -s $BASHPID | awk /cloud-init/ | wc -l)

if [[ "${CLOUD_INIT}" -ne 0 ]]; then
    echo "Rebooting in 5 seconds. Will continue with install."
    cd $DIR
    ./runonce.sh "./init.sh -c ${CLOUD_NAME} -a ${ARCH}"
    sleep 5s
    sudo shutdown -r +1
elif [[ -n "${IS_WSL2}" || "${ARCH}" == "cpu" ]]; then
    echo "First stage done. Log out, then log back in and run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
else
    echo "First stage done. Please reboot and run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
fi
