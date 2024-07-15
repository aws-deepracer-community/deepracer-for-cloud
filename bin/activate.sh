#!/bin/bash

verlte() {
  [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}

function dr-update-env {

  if [[ -f "$DIR/system.env" ]]; then
    LINES=$(grep -v '^#' $DIR/system.env)
    for l in $LINES; do
      env_var=$(echo $l | cut -f1 -d\=)
      env_val=$(echo $l | cut -f2 -d\=)
      eval "export $env_var=$env_val"
    done
  else
    echo "File system.env does not exist."
    return 1
  fi

  if [[ -f "$DR_CONFIG" ]]; then
    LINES=$(grep -v '^#' $DR_CONFIG)
    for l in $LINES; do
      env_var=$(echo $l | cut -f1 -d\=)
      env_val=$(echo $l | cut -f2 -d\=)
      eval "export $env_var=$env_val"
    done
  else
    echo "File run.env does not exist."
    return 1
  fi

  if [[ -z "${DR_RUN_ID}" ]]; then
    export DR_RUN_ID=0
  fi

  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    export DR_ROBOMAKER_TRAIN_PORT=$(expr 8080 + $DR_RUN_ID)
    export DR_ROBOMAKER_EVAL_PORT=$(expr 8180 + $DR_RUN_ID)
    export DR_ROBOMAKER_GUI_PORT=$(expr 5900 + $DR_RUN_ID)
  else
    export DR_ROBOMAKER_TRAIN_PORT="8080-8089"
    export DR_ROBOMAKER_EVAL_PORT="8080-8089"
    export DR_ROBOMAKER_GUI_PORT="5901-5920"
  fi

  # Setting the default region to ensure that things work also in the
  # non default regions.
  export AWS_DEFAULT_REGION=${DR_AWS_APP_REGION}

}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DIR="$(dirname $SCRIPT_DIR)"
export DR_DIR=$DIR

if [[ -f "$1" ]]; then
  export DR_CONFIG=$(readlink -f $1)
  dr-update-env
elif [[ -f "$DIR/run.env" ]]; then
  export DR_CONFIG="$DIR/run.env"
  dr-update-env
else
  echo "No configuration file."
  return 1
fi

# Check if Docker runs -- if not, then start it.
if [[ "$(type service 2>/dev/null)" ]]; then
  service docker status >/dev/null || sudo service docker start
fi

## Check if WSL2
if grep -qi Microsoft /proc/version && grep -q "WSL2" /proc/version; then
    IS_WSL2="yes"
fi

# Check if we will use Docker Swarm or Docker Compose
# If not defined then use Swarm
if [[ -z "${DR_DOCKER_STYLE}" ]]; then
  export DR_DOCKER_STYLE="swarm"
fi

if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
  export DR_DOCKER_FILE_SEP="-c"
  SWARM_NODE=$(docker node inspect self | jq .[0].ID -r)
  SWARM_NODE_UPDATE=$(docker node update --label-add Sagemaker=true $SWARM_NODE)
else
  export DR_DOCKER_FILE_SEP="-f"
fi

# Check if CUDA_VISIBLE_DEVICES is configured.
if [[ -n "${CUDA_VISIBLE_DEVICES}" ]]; then
  echo "WARNING: You have CUDA_VISIBLE_DEVICES defined. The will no longer work as"
  echo "         expected. To control GPU assignment use DR_ROBOMAKER_CUDA_DEVICES"
  echo "         and DR_SAGEMAKER_CUDA_DEVICES and rlcoach v5.0.1 or later."
fi

# Check if CUDA_VISIBLE_DEVICES is configured.
if [ "${DR_CLOUD,,}" == "local" ] && [ -z "${DR_MINIO_IMAGE}" ]; then
  echo "WARNING: You have not configured DR_MINIO_IMAGE in system.env."
  echo "         System will default to tag RELEASE.2022-10-24T18-35-07Z"
  export DR_MINIO_IMAGE="RELEASE.2022-10-24T18-35-07Z"
fi

# Prepare the docker compose files depending on parameters
if [[ "${DR_CLOUD,,}" == "azure" ]]; then
  export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
  export DR_MINIO_URL="http://minio:9000"
  DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
  DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
  DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
  DR_MINIO_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local.yml"
elif [[ "${DR_CLOUD,,}" == "local" ]]; then
  export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
  export DR_MINIO_URL="http://minio:9000"
  DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
  DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
  DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
  DR_MINIO_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local.yml"
elif [[ "${DR_CLOUD,,}" == "remote" ]]; then
  export DR_LOCAL_S3_ENDPOINT_URL="$DR_REMOTE_MINIO_URL"
  export DR_MINIO_URL="$DR_REMOTE_MINIO_URL"
  DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
  DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
  DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-endpoint.yml"
  DR_MINIO_COMPOSE_FILE=""
elif [[ "${DR_CLOUD,,}" == "aws" ]]; then
  DR_LOCAL_PROFILE_ENDPOINT_URL=""
  DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-aws.yml"
  DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-aws.yml"
else
  DR_LOCAL_PROFILE_ENDPOINT_URL=""
  DR_TRAIN_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-training.yml"
  DR_EVAL_COMPOSE_FILE="$DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-eval.yml"
fi

# Add host X support for Linux and WSL2
if [[ "${DR_HOST_X,,}" == "true" ]]; then
  if [[ "$IS_WSL2" == "yes" ]]; then
  
    # Check if package x11-server-utils is installed
    if ! command -v xset &> /dev/null; then
      echo "WARNING: Package x11-server-utils is not installed. Please install it to enable X11 support."
    fi
  
    if [[ "${DR_DOCKER_STYLE,,}" == "swarm" && "${DR_USE_GUI,,}" == "true" ]]; then
      echo "WARNING: Cannot use GUI in Swarm mode. Please switch to Compose mode."
    fi

    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local-xorg-wsl.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local-xorg-wsl.yml"
  else
    DR_TRAIN_COMPOSE_FILE="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local-xorg.yml"
    DR_EVAL_COMPOSE_FILE="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DIR/docker/docker-compose-local-xorg.yml"
  fi
fi

# Prevent docker swarms to restart
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
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
if [ "${DR_CLOUD,,}" == "aws" ] && [ $(aws --output json sts get-caller-identity 2>/dev/null | jq '.Arn' | awk /assumed-role/ | wc -l) -gt 0 ]; then
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
  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    docker stack deploy $DR_MINIO_COMPOSE_FILE s3
  else
    docker compose $DR_MINIO_COMPOSE_FILE -p s3 up -d
  fi

fi

## Version check
if [[ -z "$DR_SIMAPP_SOURCE" ]]; then
  echo "ERROR: Variable DR_SIMAPP_SOURCE not defined."
fi
if [[ -z "$DR_SIMAPP_VERSION" ]]; then
  echo "ERROR: Variable DR_SIMAPP_VERSION not defined."
fi
DEPENDENCY_VERSION=$(jq -r '.master_version  | select (.!=null)' $DIR/defaults/dependencies.json)

SIMAPP_VER=$(docker inspect ${DR_SIMAPP_SOURCE}:${DR_SIMAPP_VERSION} 2>/dev/null | jq -r .[].Config.Labels.version)
if [ -z "$SIMAPP_VER" ]; then SIMAPP_VER=$SIMAPP_VERSION; fi
if ! verlte $DEPENDENCY_VERSION $SIMAPP_VER; then
  echo "WARNING: Incompatible version of Deepracer Sagemaker. Expected >$DEPENDENCY_VERSION. Got $SIMAPP_VER."
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
