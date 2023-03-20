#!/usr/bin/env bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd ) # Set base Directory
trap ctrl_c INT

# Libraries
#-----------------------------------------------------------------------------------------------------------------------
source "$DIR"/lib/logging.sh
source "$DIR"/lib/common/utilities.sh

# Define Global Variables
#-----------------------------------------------------------------------------------------------------------------------

# Define log levels
ERROR=0
WARNING=1
INFO=2
DEBUG=3

LOG_LEVEL=$INFO # Set default log level

# Set default log level
set_log_level "$DIR/../system.env"

# Function to set log level from command-line argument
# This will bypass the system.env file


# Example usage:
cli_log_level "$1"


# Set default architecture
ARCH=NULL # Set default architecture
CLOUD_NAME=NULL # Set default cloud name


log_message debug "DIR: $DIR"
log_message debug "LOG_LEVEL: $LOG_LEVEL"
log_message debug "ARCH: $ARCH"
log_message debug "CLOUD_NAME: $CLOUD_NAME"


# Functions
#-----------------------------------------------------------------------------------------------------------------------

function ctrl_c() {
  # Function to handle Ctrl+C
        log_message warning "Requested to stop."
        exit 1
}

# Dependencies Check
#-----------------------------------------------------------------------------------------------------------------------

# Run Checks
detect_supported_os || exit 1

# Check for tee or add-apt-repository
if ! check_cmd "tee" || ! check_cmd "add-apt-repository"; then
    log_message warning "Tee nor add-apt-repository is installed."
    log_message info "Attempting to Installing coreutils for Tee..."
    install_package "coreutils"
fi


# Execute update and upgrade
log_message debug "Updating and Upgrading..."
update_and_upgrade

log_message info "Installing dependencies..."

# Check if jq is installed
log_message debug "Checking if jq is installed..."
check_and_install "jq"

log_message debug "Checking if lsb_release is installed..."
check_and_install "lsb_release"

# Check if curl is installed
log_message debug "Checking if curl is installed..."
check_and_install "curl"

log_message debug "Checking if awscli is installed..."
check_and_install "aws"

log_message debug "Attempting to install Boto3..."
check_and_install "python3-boto3" "apt"

# Detect Architecture
log_message debug "Detecting Architecture..."

detect_gpu

if [ $ARCH == "cpu" ]; then
    log_message info "No NVIDIA GPU detected. Will not install drivers."
else
    log_message info "NVIDIA GPU detected. Will install drivers."
fi

log_message debug "Dectecting Cloud Environment..."

detect_cloud

log_message debug "Cloud Environment: $CLOUD_NAME"

if [ $CLOUD_NAME == "local" ]; then
    log_message info "Local environment detected. Will not install cloud dependencies."
    #log_info "Local environment detected. Will not install cloud dependencies."
else
    log_message info "Cloud environment detected. Will install cloud dependencies."
    #log_info "Cloud environment detected. Will install cloud dependencies."
fi

# Check if sed is installed
log_message debug "Checking if sed is installed..."
check_and_install "sed"

# Set Distribution
# TODO: Swap maybe? IE logic for DISTRIBUTION and DISTRIBUTION_REAL
log_message debug "Setting Distribution..."
DISTRIBUTION=$(. /etc/os-release;echo $ID$VERSION_ID | sed 's/\.//')
DISTRIBUTION_REAL=$(. /etc/os-release;echo $ID$VERSION_ID)
log_message debug "DISTRIBUTION: $DISTRIBUTION"
log_message debug "DISTRIBUTION_REAL: $DISTRIBUTION_REAL"

# Adjustable Variables
#-----------------------------------------------------------------------------------------------------------------------

CUDA_KEY_NAME="3bf863cc.pub"
CUDA_SIGN="[signed-by=/etc/apt/trusted.gpg.d/$CUDA_KEY_NAME.pub]"
CUDA_KEY_URL="https://developer.download.nvidia.com/compute/cuda/repos/${DISTRIBUTION}/x86_64/3bf863cc.pub"
CUDA_REPO_URL="http://developer.download.nvidia.com/compute/cuda/repos/${DISTRIBUTION}/x86_64 /"

ML_KEY_NAME="7fa2af80.pub"
ML_SIGN="[signed-by=/etc/apt/trusted.gpg.d/$ML_KEY_NAME.pub]"
ML_KEY_URL="https://developer.download.nvidia.com/compute/machine-learning/repos/${DISTRIBUTION}/x86_64/7fa2af80.pub"
ML_REPO_URL="http://developer.download.nvidia.com/compute/machine-learning/repos/${DISTRIBUTION}/x86_64 /"

CL_KEY_NAME="nvidia-container-toolkit.gpg"
CL_KEY_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
CL_SIGN="[signed-by=/etc/apt/trusted.gpg.d/$CL_KEY_NAME]"
CL_REPO_URL='https://nvidia.github.io/libnvidia-container/stable/ubuntu18.04/$(ARCH) /'

DOCKER_KEY_NAME="docker.gpg"
DOCKER_KEY_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_SIGN="[signed-by=/etc/apt/trusted.gpg.d/$DOCKER_KEY_NAME]"
DOCKER_REPO_URL="[arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# TODO: Add support for other distributions, different versions for Ubuntu 20.04 vs 22.04?s
NVIDIA_DRIVER_VERSION="515"  #"470" # Originally Asks for 470 *does not work* on ubuntu 22.04
CUDA_VERSION="11-7"  # Originally Asks for 11-4 *does not work* on ubuntu 22.04


# Main
#-----------------------------------------------------------------------------------------------------------------------

# Prepare additional disk
if [[ "${CLOUD_NAME}" == "azure" ]];
then
    log_info "Attempting to prepare a additional disk..."
    prepare_additional_disk
fi

# Install NVIDIA Drivers
## Adding Nvidia Drivers
if [[ "${ARCH}" == "gpu" ]];
then
    log_message info "Attempting to install NVIDIA drivers..."

    if [[ "$DISTRIBUTION" == "ubuntu2004" ]]; then
        if add_gpg_key "$ML_KEY_URL" "$ML_KEY_NAME"; then
            add_dep_repo "$ML_REPO_URL" "$ML_SIGN"
        else
            add_dep_repo "$ML_REPO_URL"
        fi
    fi

    log_message debug "Adding CUDA Key..."
    cuda_check=$( add_gpg_key "${CUDA_KEY_URL}" "${CUDA_KEY_NAME}")

    log_message debug "Adding CUDA Repo..."
    if [[ "${cuda_check}" == "gpg" ]]; then
        add_dep_repo "${CUDA_REPO_URL}" "${CUDA_SIGN}"
    else
        add_dep_repo "${CUDA_REPO_URL}"
    fi

    log_message debug "Adding CUDA Key..."
    cl_check=$( add_gpg_key "${CL_KEY_URL}" "${CL_KEY_NAME}")

    log_message debug "Adding CUDA Repo..."
    if [[ "${cl_check}" == "gpg" ]]; then
        add_dep_repo "${CL_REPO_URL}" "${CL_SIGN}"
    else
        add_dep_repo "${CL_REPO_URL}"
    fi


    update_and_upgrade
    #extras_args="--no-install-recommends -o Dpkg::Options::=\"--allow-overwrite"
    install_package "nvidia-driver-${NVIDIA_DRIVER_VERSION}-server $extras_args"
    install_package "cuda-minimal-build-${CUDA_VERSION} ${extras_args}"
    log_message info "NVIDIA drivers installed."


    # Install NVIDIA Container Toolkit
    ## Adding Nvidia Container Toolkit
    log_message info "Attempting to install NVIDIA Container Toolkit..."
    install_package "nvidia-container-toolkit-base"
    log_message info "NVIDIA Container Toolkit installed."

    # Install NVIDIA Container Runtime
    ## Adding Nvidia Container Runtime
    log_message info "Attempting to install NVIDIA Container Runtime..."
    install_package "nvidia-container-runtime"

    check_cmd nvidia-ctk
    if [ $? -ne 0 ]; then
        log_message error "nvidia-ctk not found. Exiting."
        exit 1
    fi

    log_message info "Generating nvidia-container-runtime config..."
    emit_cmd sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
    if [ $? -ne 0 ]; then
        log_message error "Failed to generate nvidia-container-runtime config. Exiting."
        exit 1
    fi

fi

# Install Docker
check_cmd docker
if [ $? -ne 0 ]; then
    log_message info "Attempting to install Docker..."

    log_message debug "Adding docker Key..."
    docker_check=$( add_gpg_key "${DOCKER_KEY_URL}" "${DOCKER_KEY_NAME}")

    log_message debug "Adding CUDA Repo..."
    if [[ "${docker_check}" == "gpg" ]]; then
        add_dep_repo "${DOCKER_REPO_URL}" "${DOCKER_SIGN}"
    else
        add_dep_repo "${DOCKER_REPO_URL}"
    fi

    update_and_upgrade

    install_package "docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    log_message info "Docker installed."

    log_message info "Adding user to docker group..."
    emit_cmd sudo usermod -aG docker "$(id -un)"
    if [ $? -ne 0 ]; then
        log_message error "Failed to add user to docker group. Exiting."
        exit 1
    fi
    log_message info "User added to docker group."
else
    log_message info "Docker already installed."
fi



# Nvidia Containers
#-----------------------------------------------------------------------------------------------------------------------

if [[ "${ARCH}" == "gpu" ]];
  then

      log_message info "Attempting to setup nvidia-container-toolkit and runtime.."
      install_package "nvidia-container-toolkit"

      if [ -f "/etc/docker/daemon.json" ];
      then
          log_message info "Altering /etc/docker/daemon.json with default-runtime nvidia."
          cat /etc/docker/daemon.json | jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' | sudo tee /etc/docker/daemon.json
      else
          log_message info "Creating /etc/docker/daemon.json with default-rutime nvidia."
          emit_cmd sudo nvidia-ctk runtime configure --runtime=docker --set-as-default
      fi

      log_message info "Reloading docker daemon."
      emit_cmd sudo systemctl enable docker
      emit_cmd sudo systemctl restart docker
else
    log_message info "Not a GPU node. Skipping nvidia-container-runtime setup."
fi

## Reboot to load driver -- continue install if in cloud-init
CLOUD_INIT=$(pstree -s $BASHPID | awk /cloud-init/ | wc -l)

if [[ "$CLOUD_INIT" -ne 0 ]];
then
    log_message WARNING "Rebooting in 5 seconds. Will continue with install."
    cd $DIR
    ./runonce.sh "./init.sh -c ${CLOUD_NAME} -a ${ARCH}"
    emit_cmd sleep 5s
    sudo reboot
else
    log_message info "First stage done. Please reboot and run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
fi