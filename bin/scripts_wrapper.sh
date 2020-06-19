#!/bin/bash

function dr-upload-custom-files {
  if [[ "${DR_CLOUD,,}" == "azure" || "${DR_CLOUD,,}" == "local" ]];
  then
    if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
    then
        docker stack deploy $DR_MINIO_COMPOSE_FILE s3
    else
        docker-compose $DR_MINIO_COMPOSE_FILE -p s3 --log-level ERROR up -d
    fi
  fi
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $DIR/custom_files/ $CUSTOM_TARGET
}

function dr-upload-model {
  dr-update-env && ${DIR}/scripts/upload/upload-model.sh "$@"
}

function dr-list-aws-models {
  dr-update-env && ${DIR}/scripts/upload/list-set-models.sh "$@"
}

function dr-set-upload-model {
  dr-update-env && ${DIR}/scripts/upload/list-set-models.sh "$@"
}

function dr-download-custom-files {
  if [[ "${DR_CLOUD,,}" == "azure" || "${DR_CLOUD,,}" == "local" ]];
  then
    if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
    then
        docker stack deploy $DR_MINIO_COMPOSE_FILE s3
    else
        docker-compose $DR_MINIO_COMPOSE_FILE -p s3 --log-level ERROR up -d
    fi
  fi
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Downloading files from $CUSTOM_TARGET"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $CUSTOM_TARGET $DIR/custom_files/
}

function dr-start-training {
  dr-update-env
  bash -c "cd $DIR/scripts/training && ./start.sh $@"
}

function dr-increment-training {
  dr-update-env && ${DIR}/scripts/training/increment.sh "$@" && dr-update-env
}

function dr-stop-training {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/training && ./stop.sh"
}

function dr-start-evaluation {
  dr-update-env
  bash -c "cd $DIR/scripts/evaluation && ./start.sh $@"
}

function dr-stop-evaluation {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/evaluation && ./stop.sh"
}

function dr-start-loganalysis {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/log-analysis && ./start.sh"
}

function dr-stop-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /loganalysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/log-analysis && ./stop.sh"
  else
    echo "Log-analysis is not running."
  fi

}

function dr-logs-sagemaker {

    STACK_NAME="deepracer-$DR_RUN_ID"
    RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

    SAGEMAKER_CONTAINERS=$(docker ps | awk ' /sagemaker/ { print $1 } '| xargs )

    if [[ -n $SAGEMAKER_CONTAINERS ]];
    then
        for CONTAINER in $SAGEMAKER_CONTAINERS; do
            CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
            CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $1')
            COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $2')
            COMPOSE_FILE=$(sudo find /tmp/sagemaker -name docker-compose.yaml -exec grep -l "$RUN_NAME" {} + | grep $CONTAINER_PREFIX)
            if [[ -n $COMPOSE_FILE ]]; then
                docker logs -f $CONTAINER
            fi
        done
    else
        echo "Sagemaker is not running."
    fi

}

function dr-logs-robomaker {
    eval ROBOMAKER_ID=$(docker ps | grep "deepracer-${DR_RUN_ID}_robomaker" | cut -f1 -d\  | head -1)
    if [ -n "$ROBOMAKER_ID" ]; then
        docker logs -f $ROBOMAKER_ID
    else
        echo "Robomaker is not running."
    fi
}

function dr-logs-robomaker-debug {
    eval ROBOMAKER_ID=$(docker ps | grep "deepracer-${DR_RUN_ID}_robomaker" | cut -f1 -d\  | head -1)
    if [ -n "$ROBOMAKER_ID" ]; then
        docker logs -f $ROBOMAKER_ID 2>&1 | grep DEBUG
    else
        echo "Robomaker is not running."
    fi
}

function dr-logs-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /loganalysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    docker logs -f $LOG_ANALYSIS_ID
  else
    echo "Log-analysis is not running."
  fi

}

function dr-url-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /loganalysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    eval URL=$(docker logs $LOG_ANALYSIS_ID | perl -n -e'/(http:\/\/127\.0\.0\.1\:8888\/\?.*)/; print $1')
    echo "Log-analysis URL:"
    echo $URL
  else
    echo "Log-analysis is not running."
  fi
}
