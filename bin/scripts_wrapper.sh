#!/bin/bash

function dr-upload-custom-files {
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $DR_DIR/custom_files/ $CUSTOM_TARGET
}

function dr-upload-model {
  dr-update-env && ${DR_DIR}/scripts/upload/upload-model.sh "$@"
}

function dr-download-model {
  dr-update-env && ${DR_DIR}/scripts/upload/download-model.sh "$@"
}

function dr-upload-car-zip {
  dr-update-env && ${DR_DIR}/scripts/upload/upload-car.sh "$@"
}

function dr-list-aws-models {
  echo "Due to changes in AWS DeepRacer Console this command is no longer available."
}

function dr-set-upload-model {
  echo "Due to changes in AWS DeepRacer Console this command is no longer available."
}

function dr-increment-upload-model {
  dr-update-env && ${DR_DIR}/scripts/upload/increment.sh "$@" && dr-update-env
}

function dr-download-custom-files {
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Downloading files from $CUSTOM_TARGET"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $CUSTOM_TARGET $DR_DIR/custom_files/
}

function dr-start-training {
  dr-update-env
  $DR_DIR/scripts/training/start.sh "$@"
}

function dr-increment-training {
  dr-update-env && ${DR_DIR}/scripts/training/increment.sh "$@" && dr-update-env
}

function dr-stop-training {
  ROBOMAKER_COMMAND="" bash -c "cd $DR_DIR/scripts/training && ./stop.sh"
}

function dr-start-evaluation {
  dr-update-env
  $DR_DIR/scripts/evaluation/start.sh "$@"
}

function dr-stop-evaluation {
  ROBOMAKER_COMMAND="" bash -c "cd $DR_DIR/scripts/evaluation && ./stop.sh"
}

function dr-start-tournament {
  echo "Tournaments are no longer supported. Use Head-to-Model evaluation instead."
}

function dr-start-loganalysis {
  ROBOMAKER_COMMAND="" bash -c "cd $DR_DIR/scripts/log-analysis && ./start.sh"
}

function dr-stop-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /deepracer-analysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    ROBOMAKER_COMMAND="" bash -c "cd $DR_DIR/scripts/log-analysis && ./stop.sh"
  else
    echo "Log-analysis is not running."
  fi

}

function dr-logs-sagemaker {

  local OPTIND
  OPT_TIME="--since 5m"

  while getopts ":w:a" opt; do
    case $opt in
    w)
      OPT_WAIT=$OPTARG
      ;;
    a)
      OPT_TIME=""
      ;;
    \?)
      echo "Invalid option -$OPTARG" >&2
      ;;
    esac
  done

  SAGEMAKER_CONTAINER=$(dr-find-sagemaker)

  if [[ -z "$SAGEMAKER_CONTAINER" ]]; then
    if [[ -n "$OPT_WAIT" ]]; then
      WAIT_TIME=$OPT_WAIT
      echo "Waiting up to $WAIT_TIME seconds for Sagemaker to start up..."
      until [ -n "$SAGEMAKER_CONTAINER" ]; do
        sleep 1
        ((WAIT_TIME--))
        if [ "$WAIT_TIME" -lt 1 ]; then
          echo "Sagemaker is not running."
          return 1
        fi
        SAGEMAKER_CONTAINER=$(dr-find-sagemaker)
      done
    else
      echo "Sagemaker is not running."
      return 1
    fi
  fi

  if [[ "${DR_HOST_X,,}" == "true" && -n "$DISPLAY" ]]; then
    if [ -x "$(command -v gnome-terminal)" ]; then
      gnome-terminal --tab --title "DR-${DR_RUN_ID}: Sagemaker - ${SAGEMAKER_CONTAINER}" -- /usr/bin/bash -c "docker logs $OPT_TIME -f ${SAGEMAKER_CONTAINER}" 2>/dev/null
      echo "Sagemaker container $SAGEMAKER_CONTAINER logs opened in separate gnome-terminal. "
    elif [ -x "$(command -v x-terminal-emulator)" ]; then
      x-terminal-emulator -e /bin/sh -c "docker logs $OPT_TIME -f ${SAGEMAKER_CONTAINER}" 2>/dev/null
      echo "Sagemaker container $SAGEMAKER_CONTAINER logs opened in separate terminal. "
    else
      echo 'Could not find a defined x-terminal-emulator. Displaying inline.'
      docker logs $OPT_TIME -f $SAGEMAKER_CONTAINER
    fi
  else
    docker logs $OPT_TIME -f $SAGEMAKER_CONTAINER
  fi

}

function dr-find-sagemaker {

  STACK_NAME="deepracer-$DR_RUN_ID"
  RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

  SAGEMAKER_CONTAINERS=$(docker ps | awk ' /sagemaker/ { print $1 } ' | xargs)

  if [[ -n $SAGEMAKER_CONTAINERS ]]; then
    for CONTAINER in $SAGEMAKER_CONTAINERS; do
      CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
      CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $1')
      COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $2')
      COMPOSE_FILE=$(sudo find /tmp/sagemaker -name docker-compose.yaml -exec grep -l "$RUN_NAME" {} + | grep $CONTAINER_PREFIX)
      if [[ -n $COMPOSE_FILE ]]; then
        echo $CONTAINER
        return
      fi
    done
  fi

}

function dr-logs-robomaker {

  OPT_REPLICA=1
  OPT_EVAL=""
  local OPTIND
  OPT_TIME="--since 5m"

  while getopts ":w:n:ea" opt; do
    case $opt in
    w)
      OPT_WAIT=$OPTARG
      ;;
    n)
      OPT_REPLICA=$OPTARG
      ;;
    e)
      OPT_EVAL="-e"
      ;;
    a)
      OPT_TIME=""
      ;;
    \?)
      echo "Invalid option -$OPTARG" >&2
      ;;
    esac
  done

  ROBOMAKER_CONTAINER=$(dr-find-robomaker -n ${OPT_REPLICA} ${OPT_EVAL})

  if [[ -z "$ROBOMAKER_CONTAINER" ]]; then
    if [[ -n "$OPT_WAIT" ]]; then
      WAIT_TIME=$OPT_WAIT
      echo "Waiting up to $WAIT_TIME seconds for Robomaker #${OPT_REPLICA} to start up..."
      until [ -n "$ROBOMAKER_CONTAINER" ]; do
        sleep 1
        ((WAIT_TIME--))
        if [ "$WAIT_TIME" -lt 1 ]; then
          echo "Robomaker #${OPT_REPLICA} is not running."
          return 1
        fi
        ROBOMAKER_CONTAINER=$(dr-find-robomaker -n ${OPT_REPLICA} ${OPT_EVAL})
      done
    else
      echo "Robomaker #${OPT_REPLICA} is not running."
      return 1
    fi
  fi

  if [[ "${DR_HOST_X,,}" == "true" && -n "$DISPLAY" ]]; then
    if [ -x "$(command -v gnome-terminal)" ]; then
      gnome-terminal --tab --title "DR-${DR_RUN_ID}: Robomaker #${OPT_REPLICA} - ${ROBOMAKER_CONTAINER}" -- /usr/bin/bash -c "docker logs $OPT_TIME -f ${ROBOMAKER_CONTAINER}" 2>/dev/null
      echo "Robomaker #${OPT_REPLICA} ($ROBOMAKER_CONTAINER) logs opened in separate gnome-terminal. "
    elif [ -x "$(command -v x-terminal-emulator)" ]; then
      x-terminal-emulator -e /bin/sh -c "docker logs $OPT_TIME -f ${ROBOMAKER_CONTAINER}" 2>/dev/null
      echo "Robomaker #${OPT_REPLICA} ($ROBOMAKER_CONTAINER) logs opened in separate terminal. "
    else
      echo 'Could not find a defined x-terminal-emulator. Displaying inline.'
      docker logs $OPT_TIME -f $ROBOMAKER_CONTAINER
    fi
  else
    docker logs $OPT_TIME -f $ROBOMAKER_CONTAINER
  fi

}

function dr-find-robomaker {

  local OPTIND

  OPT_PREFIX="deepracer"

  while getopts ":n:e" opt; do
    case $opt in
    n)
      OPT_REPLICA=$OPTARG
      ;;
    e)
      OPT_PREFIX="-eval"
      ;;
    \?)
      echo "Invalid option -$OPTARG" >&2
      ;;
    esac
  done

  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    eval ROBOMAKER_ID=$(docker ps | grep "${OPT_PREFIX}-${DR_RUN_ID}_robomaker.${OPT_REPLICA}" | cut -f1 -d\  | head -1)
  else
    eval ROBOMAKER_ID=$(docker ps | grep "${OPT_PREFIX}-${DR_RUN_ID}-robomaker-${OPT_REPLICA}" | cut -f1 -d\  | head -1)
  fi

  if [ -n "$ROBOMAKER_ID" ]; then
    echo $ROBOMAKER_ID
  fi
}

function dr-get-robomaker-stats {

  local OPTIND
  OPT_REPLICA=1

  while getopts ":n:" opt; do
    case $opt in
    n)
      OPT_REPLICA=$OPTARG
      ;;
    \?)
      echo "Invalid option -$OPTARG" >&2
      ;;
    esac
  done

  eval ROBOMAKER_ID=$(dr-find-robomaker -n $OPT_REPLICA)
  if [ -n "$ROBOMAKER_ID" ]; then
    echo "Showing statistics for Robomaker #$OPT_REPLICA - container $ROBOMAKER_ID"
    docker exec -ti $ROBOMAKER_ID bash -c "gz stats"
  else
    echo "Robomaker #$OPT_REPLICA is not running."
  fi
}

function dr-logs-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /deepracer-analysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    docker logs -f $LOG_ANALYSIS_ID
  else
    echo "Log-analysis is not running."
  fi

}

function dr-url-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /deepracer-analysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    docker exec "$LOG_ANALYSIS_ID" bash -c "jupyter server list"
  else
    echo "Log-analysis is not running."
  fi
}

function dr-view-stream {
  ${DR_DIR}/utils/start-local-browser.sh "$@"
}

function dr-start-viewer {
  $DR_DIR/scripts/viewer/start.sh "$@"
}

function dr-stop-viewer {
  $DR_DIR/scripts/viewer/stop.sh "$@"
}

function dr-update-viewer {
  $DR_DIR/scripts/viewer/stop.sh "$@"
  $DR_DIR/scripts/viewer/start.sh "$@"
}

function dr-start-metrics {
  $DR_DIR/scripts/metrics/start.sh "$@"
}

function dr-stop-metrics {
  $DR_DIR/scripts/metrics/stop.sh "$@"
}