#!/bin/bash

verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

function dr-update-env {

  if [[ -f "$DIR/system.env" ]]
  then
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

  if [[ -f "$DR_CONFIG" ]]
  then
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

  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
  then
    export DR_ROBOMAKER_TRAIN_PORT=$(expr 8080 + $DR_RUN_ID)
    export DR_ROBOMAKER_EVAL_PORT=$(expr 8180 + $DR_RUN_ID)
    export DR_ROBOMAKER_GUI_PORT=$(expr 5900 + $DR_RUN_ID)
  else
    export DR_ROBOMAKER_TRAIN_PORT="8080-8089"
    export DR_ROBOMAKER_EVAL_PORT="8080-8089"
    export DR_ROBOMAKER_GUI_PORT="5901-5920"
  fi

}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIR="$( dirname $SCRIPT_DIR )"
export DR_DIR=$DIR

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
if [[ "$(type service 2> /dev/null)" ]]; then
  service docker status > /dev/null || sudo service docker start
fi

# Check if we will use Docker Swarm or Docker Compose
# If not defined then use Swarm
if [[ -z "${DR_DOCKER_STYLE}" ]]; then
  export DR_DOCKER_STYLE="swarm"
fi

if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  export DR_DOCKER_FILE_SEP="-c"
  SWARM_NODE=$(docker node inspect self | jq .[0].ID -r)
  SWARM_NODE_UPDATE=$(docker node update --label-add Sagemaker=true $SWARM_NODE)
else
  export DR_DOCKER_FILE_SEP="-f"
fi

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

source $SCRIPT_DIR/scripts_wrapper.sh

function dr-update {
   dr-update-env
}

function dr-reload {
   source $DIR/bin/activate.sh $DR_CONFIG
}
