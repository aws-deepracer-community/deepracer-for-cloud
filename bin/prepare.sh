#!/bin/bash

trap ctrl_c INT

# Functions
#-----------------------------------------------------------------------------------------------------------------------

emit_cmd() {
    local cmd="$@"
    local log_level=$LOG_LEVEL
    local debug_level=$DEBUG
    if [ "$log_level" -ge "$debug_level" ]; then
        eval "$cmd"
    else
        eval "$cmd" >/dev/null 2>&1
    fi
}

function log_message() {
    local level=$1
    local message=$2
    local log_level=$LOG_LEVEL
    local date="$(date +"%Y-%m-%d %H:%M:%S")"
    case $level in
        error)
            if [ "$log_level" -ge "$ERROR" ]; then
                echo "[ERROR] $date: $message"
            fi
            ;;
        warning)
            if [ "$log_level" -ge "$WARNING" ]; then
                echo "[WARNING] $date: $message"
            fi
            ;;
        info)
            if [ "$log_level" -ge "$INFO" ]; then
                echo "[INFO] $date: $message"
            fi
            ;;
        debug)
            if [ "$log_level" -ge "$DEBUG" ]; then
                echo "[DEBUG] $date: $message"
            fi
            ;;
        *)
            echo "Invalid log level: $level"
            ;;
    esac
}

function ctrl_c() {
  # Function to handle Ctrl+C
        log_message warning "Requested to stop."
        exit 1
}

function check_file() {
  # Function to check if a file exists

    file="$1"
    if test -f "$file"; then
       return 0 # File exists, return true
    else
        return 1 # File does not exist, return false
    fi
}

function check_dir() {
  # Function to check if a directory exists

    dir="$1"
    if test -d "$dir"; then
       return 0 # Directory exists, return true
    else
        return 1 # Directory does not exist, return false
    fi
}

function check_cmd() {
  # Function to check if a command exists
    cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        return 0 # Command exists, return true
    else
        return 1 # Command does not exist, return false
    fi
}

function get_dir() {
  # Function to get the current directory

    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
    echo "$DIR"
}


function detect_gpu() {
  # Function to detect if a GPU is present
  # TODO: This should return arch and not set a global variable?

    GPUS=$(lspci | awk '/NVIDIA/ && ( /VGA/ || /3D controller/ ) ' | wc -l )
    if [ $? -ne 0 ] || [ "$GPUS" -eq 0 ]; then
        ARCH="cpu"
    else
        ARCH="gpu"
    fi
}

function detect_cloud() {
  # Function to detect the cloud provider

    if [[ -f /var/run/cloud-init/instance-data.json ]]; then
        CLOUD_NAME=$(jq -r '.v1."cloud-name"' /var/run/cloud-init/instance-data.json)
        if [[ "${CLOUD_NAME}" == "azure" ]]; then
            export CLOUD_NAME
            export CLOUD_INSTANCETYPE=$(jq -r '.ds."meta_data".imds.compute."vmSize"' /var/run/cloud-init/instance-data.json)
        elif [[ "${CLOUD_NAME}" == "aws" ]]; then
            export CLOUD_NAME
            export CLOUD_INSTANCETYPE=$(jq -r '.ds."meta-data"."instance-type"' /var/run/cloud-init/instance-data.json)
        else
            export CLOUD_NAME=local
        fi
    else
        export CLOUD_NAME=local
    fi
}

function install_package() {
  # Function to install a package if it is not already installed

    package="$1"
    extra_args="$2"
    if ! command -v "$package" &> /dev/null; then
        emit_cmd sudo apt-get install -y "$package" "$extra_args"
        if [ $? -ne 0 ]; then
            log_message error "Failed to install $package."
            exit 1
        else
            log_message info "$package is now installed."
        fi
    else
        log_message warning "$package is already installed."
    fi
}

function update_and_upgrade() {
  # Function to update and upgrade the system

    emit_cmd sudo apt-get update --allow-unauthenticated && \
    emit_cmd sudo apt-mark hold grub-pc && \
    emit_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o \
    DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" -qq --force-yes upgrade
}

function prepare_additional_disk() {
  # Function to prepare an additional disk for use

    ADDL_DISK=$(lsblk | awk '/^sdc/ {print $1}')
    ADDL_PART=$(lsblk -l | awk -v DISK="$ADDL_DISK" '($0 ~ DISK) && ($0 ~ /part/) {print $1}')

    if [ -n "$ADDL_DISK" ] && [ -z "$ADDL_PART" ];
    then
        log_message info "Found $ADDL_DISK, preparing it for use"
        echo -e "g\nn\np\n1\n\n\nw\n" | sudo fdisk /dev/$ADDL_DISK
        sleep 1s
        ADDL_DEVICE=$(echo "/dev/"$ADDL_DISK"1")
        sudo mkfs.ext4 $ADDL_DEVICE
        sudo mkdir -p /var/lib/docker
        echo "$ADDL_DEVICE   /var/lib/docker   ext4    rw,user,auto    0    0" | sudo tee -a /etc/fstab
        mount /var/lib/docker
        if [ $? -ne 0 ]
        then
            log_message info "Error during preparing of additional disk. Exiting."
            exit 1
        fi
    elif [ -n "$ADDL_DISK" ] && [ -n "$ADDL_PART" ];
    then
        log_message info "Found $ADDL_DISK - $ADDL_PART already mounted. Installing into present drive/directory structure."
    else
        log_message info "Did not find $ADDL_DISK. Installing into present drive/directory structure."
    fi
}

function detect_supported_os() {
  # Function to detect if the OS is supported

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ $NAME == "Ubuntu" ]]; then
            if [[ $VERSION_ID == "20.04" ]] || [[ $VERSION_ID == "22.04" ]]; then
                log_message info "Supported OS detected: $NAME $VERSION"
                return 0
            fi
        fi
    fi
    log_message error "Unsupported OS detected"
    return 1
}

function check_and_install() {
  # Function to check if a package is installed and install it if not

    package="$1"
    if ! check_cmd "$package"; then
        log_message warning "$package is not installed. Attempting to install..."
        install_package "$package"

        if ! check_cmd "$package"; then
            log_message error "$package could not be installed. Exiting..."
            exit 1
        else
            log_message info "$package was successfully installed."
        fi
    fi
}

function add_gpg_key() {
  # Function to add a GPG key

  local key_url="$1"
  local key_name="$2"

  log_message info "Adding GPG key $key_name from $key_url"
  if ! emit_cmd wget -qO - "$key_url" | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/"$key_name"; then
    log_message error "Failed to add GPG key $key_name from $key_url using gpg"

    check_cmd apt-key || exit 1
    log_message info "apt-key is installed"

    log_message info "Attempting to add GPG key $key_name from $key_url using apt-key fallback"
    if ! emit_cmd sudo apt-key adv -y --fetch-keys "$key_url"; then
      log_message error "Failed to add GPG key $key_name from $key_url using apt-key"
      exit 1
    fi
    log_message info "GPG key added successfully"
    echo "apt-key"
  fi
  log_message info "GPG key added successfully"
  echo "gpg"
}

function add_dep_repo() {
  # Function to add a dependency repository

    local repo_url="$1"
    local repo_sign="$2"
    log_message info "Adding deb repository from ${repo_url}"
    if command -v add-apt-repository >/dev/null; then
      if [ -n "$repo_sign" ]; then
        emit_cmd sudo add-apt-repository -y -s "deb ${repo_sign} ${repo_url}" #> /etc/apt/sources.list.d/"$2".list
        if [ $? -ne 0 ]; then
            log_message error "Failed to add repository with add-apt-repository. Exiting."
            exit 1
        fi
      else
        emit_cmd sudo add-apt-repository -y "deb ${repo_url}" #> /etc/apt/sources.list.d/"$2".list
        if [ $? -ne 0 ]; then
            log_message error "Failed to add repository with add-apt-repository. Exiting."
            exit 1
        fi
      fi
        log_message info "added to repository with add-apt-repository"
    else
        log_message warning "add-apt-repository not found, using fallback method tee"
        emit_cmd echo "deb ${repo_url}" | sudo tee /etc/apt/sources.list.d/"$2".list
        if [ $? -ne 0 ]; then
            log_message error "Failed to add repository with tee. Exiting."
            exit 1
        fi
        log_message info "added to repository with tee"
    fi
}



# Define Global Variables
#-----------------------------------------------------------------------------------------------------------------------

# Define log levels
ERROR=0
WARNING=1
INFO=2
DEBUG=3

# Set default log level
LOG_LEVEL=$INFO

# Function to set log level from command-line argument
set_log_level() {
  if [ -z "$1" ]; then
    return
  fi

  case $1 in
    error)
      LOG_LEVEL=$ERROR
      ;;
    warning)
      LOG_LEVEL=$WARNING
      ;;
    info)
      LOG_LEVEL=$INFO
      ;;
    debug)
      LOG_LEVEL=$DEBUG
      ;;
    *)
      echo "Invalid log level: $1"
      exit 1
      ;;
  esac
}

# Example usage:
set_log_level "$1"


# Set default architecture
ARCH=NULL # Set default architecture
CLOUD_NAME=NULL # Set default cloud name


DIR=$(get_dir) # Set base Directory

log_message debug "DIR: $DIR"
log_message debug "LOG_LEVEL: $LOG_LEVEL"
log_message debug "ARCH: $ARCH"
log_message debug "CLOUD_NAME: $CLOUD_NAME"



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
install_package "python3-boto3"


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
# TODO: Swap maybe?
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
