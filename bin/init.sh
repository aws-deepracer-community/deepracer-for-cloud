#!/usr/bin/env bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd ) # Set base Directory
trap ctrl_c INT

# Libraries
#-----------------------------------------------------------------------------------------------------------------------
source "$DIR"/lib/logging.sh
source "$DIR"/lib/common/utilities.sh
source "$DIR"/lib/common/cpu.sh
source "$DIR"/lib/common/gpu.sh
source "$DIR"/lib/common/cli.sh
source "$DIR"/lib/common/docker.sh
source "$DIR"/lib/common/autorun.sh

# Functions
#-----------------------------------------------------------------------------------------------------------------------

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

function process_args() {
    if [ $# -eq 0 ]; then
        log_message error "No arguments provided."
        log_message error "Usage: $0 [-m mount_point] [-c cloud_provider] [-a architecture]"
        exit 1
    fi

    while getopts ":m:c:a:" opt; do
        case $opt in
            a)
                case $OPTARG in
                    gpu|x86_64) OPT_ARCH="$OPTARG";;
                    *) log_message error "Invalid architecture: $OPTARG" >&2; exit 1;;
                esac
                ;;
            m)
                if [ ! -d "$OPTARG" ]; then
                    log_message error "Invalid mount point: $OPTARG is not a directory" >&2
                    exit 1
                fi
                OPT_MOUNT="$OPTARG"
                ;;
            c)
                case $OPTARG in
                    aws|azure|gcp|local) OPT_CLOUD="$OPTARG";;
                    *) log_message error "Invalid cloud provider: $OPTARG" >&2; exit 1;;
                esac
                ;;
            \?)
                log_message error "Invalid option: -$OPTARG" >&2
                log_message error "Usage: $0 [-m mount_point] [-c cloud_provider] [-a architecture]" >&2
                exit 1
                ;;
        esac
    done
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

# Define the script directory
SCRIPT_DIR=get_dir

# TODO: enhance the get_dir to return the parent directory based on flags
# Return the parent directory of the script directory
INSTALL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# System Architecture
OPT_ARCH=

# Location
OPT_CLOUD=

# Define CPU Level
CPU_LEVEL=$( get_cpu_level )

# Define if Intel
CPU_INTEL=$( check_intel_cpu )

log_message debug "Log Level: $LOG_LEVEL"
log_message debug "Script Directory: $SCRIPT_DIR"
log_message debug "Install Directory: $INSTALL_DIR"
log_message debug "Architecture: $OPT_ARCH"
log_message debug "Cloud: $OPT_CLOUD"
log_message debug "CPU Level: $CPU_LEVEL"
log_message debug "CPU Intel: $CPU_INTEL"

# Dependencies Check
#-----------------------------------------------------------------------------------------------------------------------

# Check if the installed directory has spaces

if hasWhiteSpace "$INSTALL_DIR"; then
    log_message error "Deepracer-for-Cloud cannot be installed in path with spaces. Exiting."
    log_message error "Current Directory is $INSTALL_DIR"
    exit 1
else
    log_message info "Installing in $INSTALL_DIR"
fi

log_message debug "Checking if awscli is installed..."
check_and_fail "aws"


# Adjustable Variables
#-----------------------------------------------------------------------------------------------------------------------


# Process Arguments
#-----------------------------------------------------------------------------------------------------------------------

# Call our function to process the arguments
log_message debug "Processing arguments"
process_args "$@"

# Set default values
log_message debug "Setting default values"
if [ -z "$OPT_ARCH" ]; then
    OPT_ARCH="gpu"
fi

# Detect Cloud
if [[ -z "$OPT_CLOUD" ]]; then
    log_message debug "Detecting cloud provider"
    source $SCRIPT_DIR/detect.sh
    OPT_CLOUD=$CLOUD_NAME
    log_message info "Detected cloud type to be $CLOUD_NAME"
fi

# Main
#-----------------------------------------------------------------------------------------------------------------------

if check_file "$INSTALL_DIR"/DONE; then
    log_message info "Installation already completed already"
    if confirm "Do you want to re-install?"; then
        log_message info "User confirmed, Re-installing"
        emit_cmd rm -rf "$INSTALL_DIR"/DONE
    else
        log_message info "User did not confirm, Exiting"
        exit 0
    fi
fi


# Check GPU
if [[ "${OPT_ARCH}" == "gpu" ]]
then
    log_message debug "Checking for GPU"
    hasGPU=detect_gpu
    if ! $hasGPU;
    then
        # Ask for confirmation
        log_message warning "No GPU detected in docker. Configure for CPU?"
        if confirm "Are you sure you want to proceed?"; then
            # User confirmed, proceed with script
            log_message info "User confirmed, Setting to CPU."
            OPT_ARCH="cpu-avx"
        else
            # User did not confirm, exit script
            log_message error "User did not confirm, exiting script."
            exit 1
        fi
    else
        log_message info "GPU detected in docker."
    fi
fi


# Change to install directory
log_message debug "Changing to install directory"
emit_cmd cd $INSTALL_DIR

# create directory structure for docker volumes
log_message info "Creating directory structure for docker volumes"

emit_cmd mkdir -p $INSTALL_DIR/data $INSTALL_DIR/data/minio $INSTALL_DIR/data/minio/bucket
log_message debug "Created: $INSTALL_DIR/data $INSTALL_DIR/data/minio $INSTALL_DIR/data/minio/bucket"

emit_cmd mkdir -p $INSTALL_DIR/data/logs $INSTALL_DIR/data/analysis $INSTALL_DIR/data/scripts $INSTALL_DIR/tmp
log_message debug "Created: $INSTALL_DIR/data/logs $INSTALL_DIR/data/analysis $INSTALL_DIR/data/scripts $INSTALL_DIR/tmp"

emit_cmd sudo mkdir -p /tmp/sagemaker
log_message debug "Created: /tmp/sagemaker"

emit_cmd sudo chmod -R g+w /tmp/sagemaker
log_message debug "Changed permissions for /tmp/sagemaker"

# create symlink to current user's home .aws directory 
# NOTE: AWS cli must be installed for this to work
# https://docs.aws.amazon.com/cli/latest/userguide/install-linux-al2017.html

log_message info "Creating symlink to current user's home .aws directory"


# Check if .aws directory exists in current user's home directory
if [[ ! -d $(eval echo "~${USER}")/.aws ]]; then
  # Create empty .aws directory in current user's home directory if it does not exist
    log_message error "No .aws directory found in current user's home directory. please run awscli to configure. Exiting."
    exit 1
else
    log_message debug "Found .aws directory in current user's home directory."
    emit_cmd mkdir -p $(eval echo "~${USER}")/.aws $INSTALL_DIR/docker/volumes/
    log_message debug "Created: $(eval echo "~${USER}")/.aws $INSTALL_DIR/docker/volumes/"
fi

emit_cmd ln -sf $(eval echo "~${USER}")/.aws  $INSTALL_DIR/docker/volumes/
log_message debug "Created symlink: $(eval echo "~${USER}")/.aws -> $INSTALL_DIR/docker/volumes/.aws"

# create custom_files directory
log_message info "Creating custom_files directory"

emit_cmd mkdir -p $INSTALL_DIR/custom_files
log_message debug "Created: $INSTALL_DIR/custom_files"

emit_cmd cp $INSTALL_DIR/defaults/hyperparameters.json $INSTALL_DIR/custom_files/
log_message debug "Copied: $INSTALL_DIR/defaults/hyperparameters.json -> $INSTALL_DIR/custom_files/hyperparameters.json"

emit_cmd cp $INSTALL_DIR/defaults/model_metadata.json $INSTALL_DIR/custom_files/
log_message debug "Copied: $INSTALL_DIR/defaults/model_metadata.json -> $INSTALL_DIR/custom_files/model_metadata.json"

emit_cmd cp $INSTALL_DIR/defaults/reward_function.py $INSTALL_DIR/custom_files/
log_message debug "Copied: $INSTALL_DIR/defaults/reward_function.py -> $INSTALL_DIR/custom_files/reward_function.py"



# create env files
log_message info "Creating env files"

## Create system.env file
if ! check_file $INSTALL_DIR/system.env; then
    log_message info "Creating system.env file"
    emit_cmd cp $INSTALL_DIR/defaults/template-system.env $INSTALL_DIR/system.env
    log_message debug "Copied: $INSTALL_DIR/defaults/template-system.env -> $INSTALL_DIR/system.env"

else
    log_message warning "system.env file already exists"
    if confirm "Do you want to overwrite it?"; then
        # User confirmed, proceed with script
        log_message info "User confirmed, overwriting system.env file."
        emit_cmd cp $INSTALL_DIR/defaults/template-system.env $INSTALL_DIR/system.env
        log_message debug "Copied: $INSTALL_DIR/defaults/template-system.env -> $INSTALL_DIR/system.env"
    else
        # User did not confirm, exit script
        log_message info "User did not confirm, skipping system.env file."
    fi
fi

## Create run.env file
if ! check_file $INSTALL_DIR/run.env; then
    log_message info "Creating run.env file"
    emit_cmd cp $INSTALL_DIR/defaults/template-run.env $INSTALL_DIR/run.env
    log_message debug "Copied: $INSTALL_DIR/defaults/template-run.env -> $INSTALL_DIR/run.env"

else
    log_message warning "run.env file already exists"
    if confirm "Do you want to overwrite it?"; then
        # User confirmed, proceed with script
        log_message info "User confirmed, overwriting run.env file."
        emit_cmd cp $INSTALL_DIR/defaults/template-run.env $INSTALL_DIR/system.env
        log_message debug "Copied: $INSTALL_DIR/defaults/template-run.env -> $INSTALL_DIR/run.env"
    else
        # User did not confirm, exit script
        log_message info "User did not confirm, skipping run.env file."
    fi
fi

# cloud specific changes
log_message info "Implementing Cloud Target specific optimizations changes"

case "${OPT_CLOUD}" in
  aws)
    log_message debug "Cloud Target: AWS optimizations"
    AWS_EC2_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    AWS_REGION=$(echo "$AWS_EC2_AVAIL_ZONE" | sed 's/[a-z]$//')
    ;;
  azure)
    log_message debug "Cloud Target: Azure optimizations"
    AWS_REGION="us-east-1"
    sed -i "s/<LOCAL_PROFILE>/azure/g" $INSTALL_DIR/system.env
    sed -i "s/<AWS_DR_BUCKET>/not-defined/g" $INSTALL_DIR/system.env
    echo "Please run 'aws configure --profile azure' to set the credentials"
    ;;
  remote)
    log_message debug "Cloud Target: Remote optimizations"
    AWS_REGION="us-east-1"
    sed -i "s/<LOCAL_PROFILE>/minio/g" $INSTALL_DIR/system.env
    sed -i "s/<AWS_DR_BUCKET>/not-defined/g" $INSTALL_DIR/system.env
    echo "Please run 'aws configure --profile minio' to set the credentials"
    echo "Please define DR_REMOTE_MINIO_URL in system.env to point to remote minio instance."
    ;;
  *)
    log_message debug "Cloud Target: Local optimizations"
    AWS_REGION="us-east-1"
    MINIO_PROFILE="minio"
    sed -i "s/<LOCAL_PROFILE>/$MINIO_PROFILE/g" $INSTALL_DIR/system.env
    sed -i "s/<AWS_DR_BUCKET>/not-defined/g" $INSTALL_DIR/system.env
    aws configure --profile $MINIO_PROFILE get aws_access_key_id > /dev/null 2>&1
    if [[ "$?" -ne 0 ]]; then
        log_message warning "Creating default minio credentials in AWS profile '$MINIO_PROFILE'"
        aws configure --profile $MINIO_PROFILE set aws_access_key_id $(openssl rand -base64 12)
        aws configure --profile $MINIO_PROFILE set aws_secret_access_key $(openssl rand -base64 12)
        aws configure --profile $MINIO_PROFILE set region us-east-1
    fi
    ;;
esac

# set the bucket name, role and region
sed -i "s/<AWS_DR_BUCKET_ROLE>/to-be-defined/g" $INSTALL_DIR/system.env
log_message debug "Setting AWS_DR_BUCKET_ROLE to 'to-be-defined'"

sed -i "s/<CLOUD_REPLACE>/$OPT_CLOUD/g" $INSTALL_DIR/system.env
log_message debug "Setting CLOUD_REPLACE to '$OPT_CLOUD'"

sed -i "s/<REGION_REPLACE>/$AWS_REGION/g" $INSTALL_DIR/system.env
log_message debug "Setting REGION_REPLACE to '$AWS_REGION'"

# set the sagemaker tag, default to cpu if not set
log_message info "Determining SAGEMAKER_TAG"

if [[ "${OPT_ARCH}" == "gpu" ]]; then
    SAGEMAKER_TAG="gpu"
    log_message debug "Setting SAGEMAKER_TAG to 'gpu'"
elif [[ -n "${CPU_INTEL}" ]]; then
    SAGEMAKER_TAG="cpu"
    log_message debug "Setting SAGEMAKER_TAG to 'cpu'"
else
    SAGEMAKER_TAG="cpu"
    log_message debug "Defaulting SAGEMAKER_TAG to 'cpu'"
fi

log_message info "Setting SAGEMAKER_TAG to '$SAGEMAKER_TAG'"

# set proxys if required

log_message info "Setting proxy variables"

# TODO: Add checking to below to ensure that the proxy variables are set correctly
for arg in "$@"; do
    case "$arg" in
        --http_proxy=*|--https_proxy=*|--no_proxy=*)
            args+=" --build-arg ${arg#--}"
            ;;
        *)
            ;;
    esac
done


# Download docker images. Change to build statements if locally built images are desired.

# Check for defaults/dependencies.json file
log_message debug "Checking for dependencies.json file"
if ! check_file $INSTALL_DIR/defaults/dependencies.json; then
    log_message error "Could not find dependencies.json file in $INSTALL_DIR/defaults/dependencies.json"
    exit 1
fi

## set COACH_VERSION
log_message debug "Setting COACH_VERSION"
COACH_VERSION=$(jq -r '.containers.rl_coach | select (.!=null)' $INSTALL_DIR/defaults/dependencies.json)
sed -i "s/<COACH_TAG>/$COACH_VERSION/g" $INSTALL_DIR/system.env
log_message debug "Setting COACH_TAG to '$COACH_VERSION'"

## set ROBOMAKER_VERSION
log_message debug "Setting ROBOMAKER_VERSION"
ROBOMAKER_VERSION=$(jq -r '.containers.robomaker  | select (.!=null)' $INSTALL_DIR/defaults/dependencies.json)
if [ -n "$ROBOMAKER_VERSION" ]; then
    ROBOMAKER_VERSION=$ROBOMAKER_VERSION-$CPU_LEVEL
else   
    ROBOMAKER_VERSION=$CPU_LEVEL
fi
# set the ROBO_TAG in system.env
sed -i "s/<ROBO_TAG>/$ROBOMAKER_VERSION/g" $INSTALL_DIR/system.env

log_message debug "Setting  ROBOMAKER_VERSION to '$ROBOMAKER_VERSION'"

## set SAGEMAKER_VERSION
log_message debug "Setting SAGEMAKER_VERSION"
SAGEMAKER_VERSION=$(jq -r '.containers.sagemaker  | select (.!=null)' $INSTALL_DIR/defaults/dependencies.json)
if [ -n "$SAGEMAKER_VERSION" ]; then
    SAGEMAKER_VERSION=$SAGEMAKER_VERSION-$SAGEMAKER_TAG
else   
    SAGEMAKER_VERSION=$SAGEMAKER_TAG
fi
sed -i "s/<SAGE_TAG>/$SAGEMAKER_VERSION/g" $INSTALL_DIR/system.env
log_message debug "Setting SAGEMAKER_VERSION to '$SAGEMAKER_VERSION'"

pull_docker_image "awsdeepracercommunity/deepracer-rlcoach" $COACH_VERSION
pull_docker_image "awsdeepracercommunity/deepracer-robomaker" $ROBOMAKER_VERSION
pull_docker_image "awsdeepracercommunity/deepracer-sagemaker" $SAGEMAKER_VERSION


# Create the Docker Swarm
log_message info "Creating Docker Swarm"
docker_swarm_init
log_message debug "Docker Swarm initiated"


SAGEMAKER_NW='sagemaker-local'

log_message info "Creating Docker Swarm network $SAGEMAKER_NW"
setup_swarm_network $SAGEMAKER_NW
log_message debug "Docker Swarm network $SAGEMAKER_NW created"

# ensure our variables are set on startup - not for local setup.
if [[ "$OPT_CLOUD" != "local" ]]; then
    log_message info "Adding DeepRacer environment variables to .profile"
    if ! grep -q "$INSTALL_DIR/bin/activate.sh" "$HOME/.profile"; then
        echo "source $INSTALL_DIR/bin/activate.sh" >> "$HOME/.profile"
    fi
fi


## Optional auturun feature
# if using automation scripts to auto configure and run
# you must pass s3_training_location.txt to this instance in order for this to work
log_message info "Checking for Autorun scripts"
run_custom_autorun_script


# mark as done
date > "$INSTALL_DIR"/DONE 2>/dev/null
log_message info "DeepRacer setup complete, happy training!"
