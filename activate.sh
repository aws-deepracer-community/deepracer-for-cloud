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

export LOCAL_ACCESS_KEY_ID=$(aws --profile $LOCAL_S3_PROFILE configure get aws_access_key_id | xargs)
export LOCAL_SECRET_ACCESS_KEY=$(aws --profile $LOCAL_S3_PROFILE configure get aws_secret_access_key | xargs)

if [[ "${CLOUD,,}" == "azure" ]];
then
    ENDPOINT="--endpoint-url http://localhost:9000"
    COMPOSE_FILE="$DIR/docker/docker-compose.yml:$DIR/docker/docker-compose-azure.yml"
else
    COMPOSE_FILE="$DIR/docker/docker-compose.yml"
fi
export COMPOSE_FILE
export LOCAL_PROFILE_ENDPOINT_URL="--profile $LOCAL_S3_PROFILE $ENDPOINT"

function dr-upload-local-custom-files {
  if [[ "${CLOUD,,}" == "azure" ]];
  then
	  ROBOMAKER_COMMAND="" docker-compose $COMPOSE_FILES up -d minio
  fi
  eval CUSTOM_TARGET=$(echo s3://$LOCAL_S3_BUCKET/$LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  aws $LOCAL_PROFILE_ENDPOINT_URL s3 sync custom_files/ $CUSTOM_TARGET
}

function dr-start-local-training {
  bash -c "cd $DIR/scripts/training && ./start.sh"
}

function dr-stop-local-training {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/training && ./stop.sh"
}

function dr-start-local-evaluation {
  bash -c "cd $DIR/scripts/evaluation && ./start.sh"
}

function dr-stop-local-evaluation {
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
