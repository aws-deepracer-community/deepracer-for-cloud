#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# create directory structure for docker volumes
if ! (mount | grep /mnt > /dev/null); then
  mount /mnt
fi
sudo mkdir -p /mnt/deepracer /mnt/deepracer/recording
sudo chown $(id -u):$(id -g) /mnt/deepracer 

if [[ -f "$DIR/current-run.env" ]]
then
    export $(grep -v '^#' $DIR/current-run.env | xargs)
else
    echo "File current-run.env does not exist."
    exit 1
fi


if [[ "${CLOUD,,}" == "azure" ]];
then
    LOCAL_PROFILE_ENDPOINT_URL="--profile $LOCAL_S3_PROFILE --endpoint-url http://localhost:9000"
    COMPOSE_FILE="$DIR/docker/docker-compose.yml:$DIR/docker/docker-compose-azure.yml"
else
    LOCAL_PROFILE_ENDPOINT_URL=""
    COMPOSE_FILE="$DIR/docker/docker-compose.yml"
fi

## Check if we have an AWS IAM assumed role, or if we need to set specific credentials.
if [ $(aws sts get-caller-identity | jq '.Arn' | awk /assumed-role/ | wc -l) -eq 0 ];
then
    export LOCAL_ACCESS_KEY_ID=$(aws --profile $LOCAL_S3_PROFILE configure get aws_access_key_id | xargs)
    export LOCAL_SECRET_ACCESS_KEY=$(aws --profile $LOCAL_S3_PROFILE configure get aws_secret_access_key | xargs)
    COMPOSE_FILE="$COMPOSE_FILE:$DIR/docker/docker-compose-keys.yml"
fi

export COMPOSE_FILE
export LOCAL_PROFILE_ENDPOINT_URL

function dr-upload-custom-files {
  if [[ "${CLOUD,,}" == "azure" ]];
  then
	  ROBOMAKER_COMMAND="" docker-compose $COMPOSE_FILES up -d minio
  fi
  eval CUSTOM_TARGET=$(echo s3://$LOCAL_S3_BUCKET/$LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  aws $LOCAL_PROFILE_ENDPOINT_URL s3 sync $DIR/custom_files/ $CUSTOM_TARGET
}

function dr-upload-logs {
  if [[ "${CLOUD,,}" == "azure" ]];
  then
	  ROBOMAKER_COMMAND="" docker-compose $COMPOSE_FILES up -d minio
  fi
  eval CUSTOM_TARGET=$(echo s3://$LOCAL_S3_BUCKET/$LOCAL_S3_LOGS_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  aws $LOCAL_PROFILE_ENDPOINT_URL s3 sync /mnt/deepracer/robo/checkpoint/log $CUSTOM_TARGET --exclude "*" --include "rl_coach*.log*" --no-follow-symlinks
}

function dr-download-custom-files {
  if [[ "${CLOUD,,}" == "azure" ]];
  then
	  ROBOMAKER_COMMAND="" docker-compose $COMPOSE_FILES up -d minio
  fi
  eval CUSTOM_TARGET=$(echo s3://$LOCAL_S3_BUCKET/$LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Downloading files from $CUSTOM_TARGET"
  aws $LOCAL_PROFILE_ENDPOINT_URL s3 sync $CUSTOM_TARGET $DIR/custom_files/
}

function dr-start-training {
  bash -c "cd $DIR/scripts/training && ./start.sh"
}

function dr-stop-training {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/training && ./stop.sh"
}

function dr-start-evaluation {
  bash -c "cd $DIR/scripts/evaluation && ./start.sh"
}

function dr-stop-evaluation {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/evaluation && ./stop.sh"
}

function dr-start-loganalysis {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/log-analysis && ./start.sh"
}

function dr-stop-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /log-analysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/log-analysis && ./stop.sh"
  else
    echo "Log-analysis is not running."
  fi

}

function dr-logs-sagemaker {
    eval SAGEMAKER_ID=$(docker ps | awk ' /sagemaker/ { print $1 }')
    if [ -n "$SAGEMAKER_ID" ]; then
        docker logs -f $SAGEMAKER_ID
    else
        echo "Sagemaker is not running."
    fi
}

function dr-logs-robomaker {
    eval ROBOMAKER_ID=$(docker ps | awk ' /robomaker/ { print $1 }')
    if [ -n "$ROBOMAKER_ID" ]; then
        docker logs -f $ROBOMAKER_ID
    else
        echo "Robomaker is not running."
    fi
}

function dr-logs-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /log-analysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    docker logs -f $LOG_ANALYSIS_ID
  else
    echo "Log-analysis is not running."
  fi
  
}

function dr-logs-proxy-start {
   docker-compose -f $DIR/docker/docker-compose-log.yml up -d
}

function dr-logs-proxy-stop {
   docker-compose -f $DIR/docker/docker-compose-log.yml down
}

function dr-update {
   source $DIR/activate.sh
}
