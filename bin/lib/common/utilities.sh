# Library for Utility functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# Utility Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

emit_cmd() {
  # Emit a command to the console or hid it
    local cmd="$@"
    local log_level=$LOG_LEVEL
    local debug_level=$DEBUG
    if [ "$log_level" -ge "$debug_level" ]; then
        eval "$cmd"
    else
        eval "$cmd" >/dev/null 2>&1
    fi
}

function check_file() {
  # Function to check if a file exists

    local file="$1"
    if test -f "$file"; then
       true # File exists, return true
    else
       false # File does not exist, return false
    fi
}

function check_dir() {
  # Function to check if a directory exists

    local dir="$1"
    if test -d "$dir"; then
       return 0 # Directory exists, return true
    else
        return 1 # Directory does not exist, return false
    fi
}

function check_cmd() {
  # Function to check if a command exists
    local cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        return 0 # Command exists, return true
    else
        return 1 # Command does not exist, return false
    fi
}

function get_dir() {
  # Function to get the current directory

    local DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
    echo "$DIR"
}

function detect_gpu() {
  # Function to detect if a GPU is present
  # TODO: This should return arch and not set a global variable?

    local GPUS=$(lspci | awk '/NVIDIA/ && ( /VGA/ || /3D controller/ ) ' | wc -l )
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

# TODO: Change to true and false, instead of 0 and 1
is_package_installed() {
  # Function to check if a package is installed

    local package_name="$1"
    if dpkg -l | grep -q "^ii.*${package_name}[[:space:]]"; then
        log_message debug "$package_name is installed."
        return 0  # Package is installed
    else
        log_message debug "$package_name is not installed."
        return 1  # Package is not installed
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
    isapt="$2"

    if ! [[ "$isapt" ]]; then
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
    else
      if ! is_package_installed "$package"; then
          log_message warning "$package is not installed. Attempting to install..."
          install_package "$package"

          if ! is_package_installed "$package"; then
              log_message error "$package could not be installed. Exiting..."
              exit 1
          else
              log_message info "$package was successfully installed."
          fi
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

function hasWhiteSpace() {
    # Function to check if a string has whitespace

    local checkstring="$1"
    if [[ "$checkstring" == *\ * ]]; then
        log_message debug "String has whitespace: $checkstring"
        return 0 # Has whitespace
    else
        log_message debug "String has no whitespace: $checkstring"
        return 1 # No whitespace
    fi
}

function check_and_fail() {
    # Function to check if a package is installed and fail if not

    local package="$1"
    local isapt="$2"

    if ! [[ "$isapt" ]]; then
        if ! check_cmd "$package"; then
            log_message error "$package is not installed. Exiting..."
            exit 1
        else
            true
        fi
    else
        if ! is_package_installed "$package"; then
            log_message error "$package is not installed. Exiting..."
            exit 1
        else
            true
        fi
    fi
}