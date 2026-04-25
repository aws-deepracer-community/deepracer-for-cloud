#!/usr/bin/env bash

function dr-upload-custom-files {
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  if [[ -z $DR_EXPERIMENT_NAME ]]; then
    aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $DR_DIR/custom_files/ $CUSTOM_TARGET
  else
    aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $DR_DIR/experiments/$DR_EXPERIMENT_NAME/custom_files/ $CUSTOM_TARGET
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
  bash -c "cd $DR_DIR/scripts/training && ./stop.sh"
}

function dr-start-evaluation {
  dr-update-env
  $DR_DIR/scripts/evaluation/start.sh "$@"
}

function dr-stop-evaluation {
  bash -c "cd $DR_DIR/scripts/evaluation && ./stop.sh"
}

function dr-stop-all {
  # Step 1: Stop all stacks (swarm) or all compose projects (compose)
  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    docker stack ls --format '{{.Name}}' | while read -r STACK; do
      echo "Removing stack: $STACK"
      docker stack rm "$STACK"
    done
  else
    while IFS=$'\t' read -r NAME CONFIGS; do
      echo "Stopping compose project: $NAME"
      local CONFIG_FLAGS
      CONFIG_FLAGS=$(echo "$CONFIGS" | tr ',' '\n' | sed 's/^/-f /' | tr '\n' ' ')
      docker compose $CONFIG_FLAGS -p "$NAME" down
    done < <(docker compose ls --format json 2>/dev/null \
      | jq -r '.[] | [.Name, .ConfigFiles] | @tsv')
  fi

  # Step 2: Stop the s3/minio stack if still running
  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    if docker stack ls --format '{{.Name}}' | grep -qx 's3'; then
      echo "Removing stack: s3"
      docker stack rm s3
    fi
  else
    if docker compose ls --format json 2>/dev/null | jq -e '.[] | select(.Name == "s3")' >/dev/null 2>&1; then
      echo "Stopping compose project: s3"
      docker compose -p s3 down
    fi
  fi
  echo "Waiting 10 seconds for stacks and services to stop..."
  sleep 10
  # Step 3: Stop any remaining containers still attached to sagemaker-local
  local REMAINING
  REMAINING=$(docker network inspect sagemaker-local --format '{{json .Containers}}' 2>/dev/null \
    | jq -r 'keys[] | select(test("^[0-9a-f]{64}$"))' 2>/dev/null)
  if [[ -n "$REMAINING" ]]; then
    echo "Stopping remaining containers on sagemaker-local:"
    echo "$REMAINING" | while read -r CONTAINER_ID; do
      local CONTAINER_NAME
      CONTAINER_NAME=$(docker inspect --format '{{.Name}}' "$CONTAINER_ID" | sed 's|^/||')
      echo "  Stopping: $CONTAINER_NAME"
      docker stop "$CONTAINER_ID"
    done
  fi
}

function dr-start-tournament {
  echo "Tournaments are no longer supported. Use Head-to-Model evaluation instead."
}

function dr-start-loganalysis {
  bash -c "cd $DR_DIR/scripts/log-analysis && ./start.sh"
}

function dr-stop-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /deepracer-analysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    bash -c "cd $DR_DIR/scripts/log-analysis && ./stop.sh"
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

  if [[ "$TERM_PROGRAM" == "vscode" ]]; then
    echo "VS Code terminal detected. Displaying Sagemaker logs inline."
    docker logs $OPT_TIME -f $SAGEMAKER_CONTAINER
  elif [[ "${DR_HOST_X,,}" == "true" && -n "$DISPLAY" ]]; then
    if [ -x "$(command -v gnome-terminal)" ]; then
      gnome-terminal --tab --title "DR-${DR_RUN_ID}: Sagemaker - ${SAGEMAKER_CONTAINER}" -- /usr/bin/bash -c "docker logs $OPT_TIME -f ${SAGEMAKER_CONTAINER}" 2>/dev/null
      echo "Sagemaker container $SAGEMAKER_CONTAINER logs opened in separate gnome-terminal. "
    elif [ -x "$(command -v x-terminal-emulator)" ]; then
      x-terminal-emulator -e /bin/sh -c "docker logs $OPT_TIME -f ${SAGEMAKER_CONTAINER}" 2>/dev/null
      echo "Sagemaker container $SAGEMAKER_CONTAINER logs opened in separate terminal. "
    else
      echo 'Could not find a terminal emulator. Displaying inline.'
      docker logs $OPT_TIME -f $SAGEMAKER_CONTAINER
    fi
  else
    docker logs $OPT_TIME -f $SAGEMAKER_CONTAINER
  fi

}

function dr-find-sagemaker {

  STACK_NAME="deepracer-$DR_RUN_ID"
  RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

  SAGEMAKER_CONTAINERS=$(docker ps | awk ' /simapp/ { print $1 } ' | xargs)

  if [[ -n "$SAGEMAKER_CONTAINERS" ]]; then
      for CONTAINER in $SAGEMAKER_CONTAINERS; do
          CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
          CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)-(algo-(.)-(.*))/; print $1')
          COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)-(algo-(.)-(.*))/; print $2')

          if [[ -n "$COMPOSE_SERVICE_NAME" ]]; then
              COMPOSE_FILES=$(sudo find /tmp/sagemaker -name docker-compose.yaml -exec grep -l "$COMPOSE_SERVICE_NAME" {} +)
              for COMPOSE_FILE in $COMPOSE_FILES; do
                  if sudo grep -q "RUN_ID=${DR_RUN_ID}" $COMPOSE_FILE && sudo grep -q "${RUN_NAME}" $COMPOSE_FILE; then
                      echo $CONTAINER
                  fi
              done
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

  if [[ "$TERM_PROGRAM" == "vscode" ]]; then
    echo "VS Code terminal detected. Displaying Robomaker #${OPT_REPLICA} logs inline."
    docker logs $OPT_TIME -f $ROBOMAKER_CONTAINER
  elif [[ "${DR_HOST_X,,}" == "true" && -n "$DISPLAY" ]]; then
    if [ -x "$(command -v gnome-terminal)" ]; then
      gnome-terminal --tab --title "DR-${DR_RUN_ID}: Robomaker #${OPT_REPLICA} - ${ROBOMAKER_CONTAINER}" -- /usr/usr/bin/env bash -c "docker logs $OPT_TIME -f ${ROBOMAKER_CONTAINER}" 2>/dev/null
      echo "Robomaker #${OPT_REPLICA} ($ROBOMAKER_CONTAINER) logs opened in separate gnome-terminal. "
    elif [ -x "$(command -v x-terminal-emulator)" ]; then
      x-terminal-emulator -e /bin/sh -c "docker logs $OPT_TIME -f ${ROBOMAKER_CONTAINER}" 2>/dev/null
      echo "Robomaker #${OPT_REPLICA} ($ROBOMAKER_CONTAINER) logs opened in separate terminal. "
    else
      echo 'Could not find a terminal emulator. Displaying inline.'
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
  LOG_ANALYSIS_ID=$(docker ps --filter "name=deepracer-analysis" --format "{{.ID}}" | head -1)
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    URL=$(docker logs "$LOG_ANALYSIS_ID" 2>&1 | grep -oE 'http://127\.0\.0\.1:[0-9]+[^ ]*token=[a-f0-9]+' | tail -1)
    if [ -n "$URL" ]; then
      echo "${URL/127.0.0.1/localhost}"
    else
      echo "Jupyter URL not found yet. Try again in a moment."
    fi
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