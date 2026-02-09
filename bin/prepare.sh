#!/usr/bin/env bash

set -euo pipefail
trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

export DEBIAN_FRONTEND=noninteractive
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Only allow supported Ubuntu versions
. /etc/os-release
SUPPORTED_VERSIONS=("22.04" "24.04" "24.10" "25.04" "25.10")
DISTRIBUTION=${ID}${VERSION_ID//./}
UBUNTU_MAJOR_VERSION=$(echo $VERSION_ID | cut -d. -f1)
UBUNTU_MINOR_VERSION=$(echo $VERSION_ID | cut -d. -f2)
if [[ "$ID" == "ubuntu" ]]; then
    VERSION_OK=false
    for V in "${SUPPORTED_VERSIONS[@]}"; do
        if [[ "$VERSION_ID" == "$V" ]]; then
            VERSION_OK=true
            break
        fi
    done
    if [[ "$VERSION_OK" != true ]]; then
        echo "ERROR: Ubuntu $VERSION_ID is not a supported version. Supported versions: ${SUPPORTED_VERSIONS[*]}"
        exit 1
    fi
fi

## Check if WSL2
IS_WSL2=""
if grep -qi Microsoft /proc/version && grep -q "WSL2" /proc/version; then
    IS_WSL2="yes"
fi

# Remove needrestart in all Ubuntu 2x.04/2x.10+ (future-proof)
if [[ "${ID}" == "ubuntu" && ${UBUNTU_MAJOR_VERSION} -ge 22 && -z "${IS_WSL2}" ]]; then
    sudo apt remove -y needrestart || true
fi

## Patch system
sudo apt update && sudo apt-mark hold grub-pc && sudo apt -y -o \
    DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" -qq upgrade

## Install required packages
sudo apt install --no-install-recommends -y jq python3-boto3 screen git curl

## Install AWS CLI
if [[ "${ID}" == "ubuntu" && ( ${UBUNTU_MAJOR_VERSION} -eq 22 ) ]]; then
    sudo apt install -y awscli
else
    if command -v snap >/dev/null 2>&1; then
        sudo snap install aws-cli --classic
    else
        echo "WARNING: snap not available, AWS CLI not installed"
    fi
fi

## Detect cloud
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
    DRIVER_OK=false
    # Find all installed nvidia-driver-XXX packages (status 'ii'), extract version, and check if >= 525
    for PKG in $(dpkg -l | awk '$1 == "ii" && /nvidia-driver-[0-9]+/ {print $2}'); do
        DRIVER_VER=$(echo "${PKG}" | sed -E 's/nvidia-driver-([0-9]+).*/\1/')
        if [[ ${DRIVER_VER} -ge 560 ]]; then
            echo "NVIDIA driver ${DRIVER_VER} already installed."
            DRIVER_OK=true
            break
        fi
    done
    if [[ "${DRIVER_OK}" != true ]]; then
        # Try to install the highest available driver >= 560
        HIGHEST_DRIVER=$(apt-cache search --names-only '^nvidia-driver-[0-9]+$' | awk '{print $1}' | grep -oE '[0-9]+$' | awk '$1 >= 560' | sort -nr | head -n1)
        if [[ -n "${HIGHEST_DRIVER}" ]]; then
            sudo apt install -y "nvidia-driver-${HIGHEST_DRIVER}" --no-install-recommends -o Dpkg::Options::="--force-overwrite"
        elif apt-cache show nvidia-driver-560-server &>/dev/null; then
            sudo apt install -y nvidia-driver-560-server --no-install-recommends -o Dpkg::Options::="--force-overwrite"
        else
            echo "No supported NVIDIA driver >= 560 found for this Ubuntu version."
            exit 1
        fi
    fi
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
        echo "Altering /etc/docker/daemon.json with default-runtime nvidia."
        cat /etc/docker/daemon.json | jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' | sudo tee /etc/docker/daemon.json
    else
        echo "Creating /etc/docker/daemon.json with default-runtime nvidia."
        sudo cp "${DIR}/../defaults/docker-daemon.json" /etc/docker/daemon.json
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
sudo usermod -a -G docker "$(id -un)"

## Reboot to load driver -- continue install if in cloud-init
CLOUD_INIT=$(pstree -s $BASHPID | awk /cloud-init/ | wc -l)

if [[ "${CLOUD_INIT}" -ne 0 ]]; then
    echo "Rebooting in 5 seconds. Will continue with install."
    cd "${DIR}"
    ./runonce.sh "./init.sh -c ${CLOUD_NAME} -a ${ARCH}"
    sleep 5s
    sudo shutdown -r +1
elif [[ -n "${IS_WSL2}" || "${ARCH}" == "cpu" ]]; then
    echo "First stage done. Log out, then log back in and run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
    echo "Note: You may need to log out and back in for docker group membership to take effect."
else
    echo "First stage done. Please reboot and run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
    echo "Note: Reboot is required for NVIDIA drivers and docker group membership to take effect."
fi
