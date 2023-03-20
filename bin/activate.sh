#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIR="$( dirname $SCRIPT_DIR )"
export DR_DIR=$DIR

# Libraries
#-----------------------------------------------------------------------------------------------------------------------

source "$SCRIPT_DIR"/lib/logging.sh
source "$SCRIPT_DIR"/lib/common/utilities.sh
source "$SCRIPT_DIR"/lib/common/docker.sh
source "$SCRIPT_DIR"/lib/common/minio.sh
source "$SCRIPT_DIR"/lib/common/gpu.sh

# Functions
#-----------------------------------------------------------------------------------------------------------------------

# Define Global Variables
#-----------------------------------------------------------------------------------------------------------------------
# Define log levels
ERROR=0
WARNING=1
INFO=2
DEBUG=3


LOG_LEVEL=$INFO # Set default log level

# Set default log level
set_log_level "$DR_DIR/system.env"



# Dependencies Check
#-----------------------------------------------------------------------------------------------------------------------
check_and_fail "docker"



# Adjustable Variables
#-----------------------------------------------------------------------------------------------------------------------

MINIO_VERSION="RELEASE.2022-10-24T18-35-07Z"

# Process Arguments
#-----------------------------------------------------------------------------------------------------------------------

# Main
#-----------------------------------------------------------------------------------------------------------------------

verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

function dr-update-env {
  # Import system environment variables from `system.env`
  log_message info "Updating system environment variables"
  if [[ -f "$DIR/system.env" ]]; then
    log_message info "Importing system environment variables from system.env"
    while read -r line; do
      if [[ "$line" != \#* && "$line" != "" ]]; then
        export "${line?}"
        log_message debug " Exporting: $line"
      fi
    done < "$DIR/system.env"
    log_message debug "Done importing system environment variables from system.env"
  else
    log_message error "File system.env does not exist."
    return 1
  fi

  # Import environment variables from `run.env`
  log_message info "Importing environment variables from run.env"
  if [[ -f "$DR_CONFIG" ]]; then
    log_message debug "Importing environment variables from run.env"
    while read -r line; do
      if [[ "$line" != \#* && "$line" != "" ]]; then
        export "$line"
        log_message debug " Exporting: $line"
      fi
    done < "$DR_CONFIG"
    log_message debug "Done importing environment variables from run.env"
  else
    log_message error "File run.env does not exist."
    return 1
  fi

  # Set default value for DR_RUN_ID if it's not set
  DR_RUN_ID=${DR_RUN_ID:-0}
  log_message debug "DR_RUN_ID: $DR_RUN_ID"

  # Set ports for RoboMaker based on DR_DOCKER_STYLE
  log_message info "Setting ports for RoboMaker"
  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    log_message debug "DR_DOCKER_STYLE: swarm"
    export DR_ROBOMAKER_TRAIN_PORT=$((8080 + DR_RUN_ID))
    log_message debug "DR_ROBOMAKER_TRAIN_PORT: $DR_ROBOMAKER_TRAIN_PORT"
    export DR_ROBOMAKER_EVAL_PORT=$((8180 + DR_RUN_ID))
    log_message debug "DR_ROBOMAKER_EVAL_PORT: $DR_ROBOMAKER_EVAL_PORT"
    export DR_ROBOMAKER_GUI_PORT=$((5900 + DR_RUN_ID))
    log_message debug "DR_ROBOMAKER_GUI_PORT: $DR_ROBOMAKER_GUI_PORT"
  else
    export DR_ROBOMAKER_TRAIN_PORT="8080-8089"
    log_message debug "DR_ROBOMAKER_TRAIN_PORT: $DR_ROBOMAKER_TRAIN_PORT"
    export DR_ROBOMAKER_EVAL_PORT="8080-8089"
    log_message debug "DR_ROBOMAKER_EVAL_PORT: $DR_ROBOMAKER_EVAL_PORT"
    export DR_ROBOMAKER_GUI_PORT="5901-5920"
    log_message debug "DR_ROBOMAKER_GUI_PORT: $DR_ROBOMAKER_GUI_PORT"
  fi
  log_message info "Done updating the environment"
}


#SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
#DIR="$( dirname $SCRIPT_DIR )"
#export DR_DIR=$DIR

if [[ -f "$1" ]];
then
  export DR_CONFIG=$(readlink -f $1)
  dr-update-env
elif [[ -f "$DIR/run.env" ]];
then
  export DR_CONFIG="$DIR/run.env"
  dr-update-env
else
  echo "No configuration file."
  return 1
fi

# Check if Docker runs -- if not, then start it.
check_and_start_docker

# Check if we will use Docker Swarm or Docker Compose
# If not defined then use Swarm
log_message debug "Checking if DR_DOCKER_STYLE is defined."
if [[ -z "${DR_DOCKER_STYLE}" ]]; then
  log_message debug "DR_DOCKER_STYLE is not defined. Defaulting to swarm."
  export DR_DOCKER_STYLE="swarm"
fi

log_message info "DR_DOCKER_STYLE is set to ${DR_DOCKER_STYLE}."

# Check if we will use Docker Swarm or Docker Compose
set_docker_style

# Check if CUDA_VISIBLE_DEVICES is configured.
alert_cuda_devices

# Check if CUDA_VISIBLE_DEVICES is configured.
alert_minio_image $MINIO_VERSION

# Prepare the docker compose files depending on parameters
if [[ "${DR_CLOUD,,}" == "azure" ]];
then
    export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
    export DR_MINIO_URL="http://minio:9000"
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
    DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
    DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
    DR_MINIO_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-azure.yml"
elif [[ "${DR_CLOUD,,}" == "local" ]];
then
    export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
    export DR_MINIO_URL="http://minio:9000"
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
    DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
    DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
    DR_MINIO_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local.yml"
elif [[ "${DR_CLOUD,,}" == "remote" ]];
then
    export DR_LOCAL_S3_ENDPOINT_URL="$DR_REMOTE_MINIO_URL"
    export DR_MINIO_URL="$DR_REMOTE_MINIO_URL"
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
    DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
    DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
    DR_MINIO_COMPOSE_FILE=""
else
    DR_LOCAL_PROFILE_ENDPOINT_URL=""
    DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml"
    DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml"
fi

# Prevent docker swarms to restart
if [[ "${DR_HOST_X,,}" == "true" ]];
then
    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local-xorg.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local-xorg.yml"
fi

# Prevent docker swarms to restart
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training-swarm.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval-swarm.yml"
fi

# Enable logs in CloudWatch
if [[ "${DR_CLOUD_WATCH_ENABLE,,}" == "true" ]]; then
    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-cwlog.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-cwlog.yml"
fi

# Enable local simapp mount
if [[ -d "${DR_ROBOMAKER_MOUNT_SIMAPP_DIR,,}" ]]; then
    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-simapp.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-simapp.yml"
fi

## Check if we have an AWS IAM assumed role, or if we need to set specific credentials.
if [ "${DR_CLOUD,,}" == "aws" ] && [ $(aws --output json sts get-caller-identity 2> /dev/null | jq '.Arn' | awk /assumed-role/ | wc -l ) -gt 0 ];
then
    export DR_LOCAL_S3_AUTH_MODE="role"
else 
    export DR_LOCAL_ACCESS_KEY_ID=$(aws --profile $DR_LOCAL_S3_PROFILE configure get aws_access_key_id | xargs)
    export DR_LOCAL_SECRET_ACCESS_KEY=$(aws --profile $DR_LOCAL_S3_PROFILE configure get aws_secret_access_key | xargs)
    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-keys.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-keys.yml"
    export DR_UPLOAD_PROFILE="--profile $DR_UPLOAD_S3_PROFILE"
    export DR_LOCAL_S3_AUTH_MODE="profile"
fi

export DR_TRAIN_COMPOSE_FILE
export DR_EVAL_COMPOSE_FILE
export DR_LOCAL_PROFILE_ENDPOINT_URL

if [[ -n "${DR_MINIO_COMPOSE_FILE}" ]]; then
    export MINIO_UID=$(id -u)
    export MINIO_USERNAME=$(id -u -n)
    export MINIO_GID=$(id -g)
    export MINIO_GROUPNAME=$(id -g -n)
    if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
    then
        docker stack deploy $DR_MINIO_COMPOSE_FILE s3
    else
        docker-compose $DR_MINIO_COMPOSE_FILE -p s3 --log-level ERROR up -d
    fi

fi

## Version check
DEPENDENCY_VERSION=$(jq -r '.master_version  | select (.!=null)' $DIR/defaults/dependencies.json)

SAGEMAKER_VER=$(docker inspect awsdeepracercommunity/deepracer-sagemaker:$DR_SAGEMAKER_IMAGE 2> /dev/null | jq -r .[].Config.Labels.version)
if [ -z "$SAGEMAKER_VER" ]; then SAGEMAKER_VER=$DR_SAGEMAKER_IMAGE; fi
if ! verlte $DEPENDENCY_VERSION $SAGEMAKER_VER; then
  echo "WARNING: Incompatible version of Deepracer Sagemaker. Expected >$DEPENDENCY_VERSION. Got $SAGEMAKER_VER."
fi

ROBOMAKER_VER=$(docker inspect awsdeepracercommunity/deepracer-robomaker:$DR_ROBOMAKER_IMAGE 2> /dev/null | jq -r .[].Config.Labels.version )
if [ -z "$ROBOMAKER_VER" ]; then ROBOMAKER_VER=$DR_ROBOMAKER_IMAGE; fi
if ! verlte $DEPENDENCY_VERSION $ROBOMAKER_VER; then
  echo "WARNING: Incompatible version of Deepracer Robomaker. Expected >$DEPENDENCY_VERSION. Got $ROBOMAKER_VER."
fi

COACH_VER=$(docker inspect awsdeepracercommunity/deepracer-rlcoach:$DR_COACH_IMAGE 2> /dev/null | jq -r .[].Config.Labels.version)
if [ -z "$COACH_VER" ]; then COACH_VER=$DR_COACH_IMAGE; fi
if ! verlte $DEPENDENCY_VERSION $COACH_VER; then
  echo "WARNING: Incompatible version of Deepracer-for-Cloud Coach. Expected >$DEPENDENCY_VERSION. Got $COACH_VER."
fi

## Create a dr-local-aws command
alias dr-local-aws='aws $DR_LOCAL_PROFILE_ENDPOINT_URL'

source $SCRIPT_DIR/scripts_wrapper.sh

function dr-update {
   dr-update-env
}

function dr-reload {
   source $DIR/bin/activate.sh $DR_CONFIG
}
