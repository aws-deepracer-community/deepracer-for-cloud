#!/usr/bin/env bash

source $DR_DIR/bin/scripts_wrapper.sh

usage() {
  echo "Usage: $0 [-q] [-c]"
  echo "       -q        Quiet - does not start log tracing."
  echo "       -c        Clone - copies model into new prefix before evaluating."
  exit 1
}

trap ctrl_c INT

function ctrl_c() {
  echo "Requested to stop."
  exit 1
}

while getopts ":qc" opt; do
  case $opt in
  q)
    OPT_QUIET="QUIET"
    ;;
  c)
    OPT_CLONE="CLONE"
    ;;
  h)
    usage
    ;;
  \?)
    echo "Invalid option -$OPTARG" >&2
    usage
    ;;
  esac
done

# set evaluation specific environment variables
STACK_NAME="deepracer-eval-$DR_RUN_ID"
STACK_CONTAINERS=$(docker stack ps $STACK_NAME 2>/dev/null | wc -l)
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
  if [[ "$STACK_CONTAINERS" -gt 1 ]]; then
    echo "ERROR: Processes running in stack $STACK_NAME. Stop evaluation with dr-stop-evaluation."
    exit 1
  fi
fi

# clone if required
if [ -n "$OPT_CLONE" ]; then
  echo "Cloning model into s3://$DR_LOCAL_S3_BUCKET/${DR_LOCAL_S3_MODEL_PREFIX}-E"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX/model s3://$DR_LOCAL_S3_BUCKET/${DR_LOCAL_S3_MODEL_PREFIX}-E/model
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX/ip s3://$DR_LOCAL_S3_BUCKET/${DR_LOCAL_S3_MODEL_PREFIX}-E/ip
  export DR_LOCAL_S3_MODEL_PREFIX=${DR_LOCAL_S3_MODEL_PREFIX}-E
fi

# set evaluation specific environment variables
S3_PATH="s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX"

export ROBOMAKER_COMMAND="./run.sh run evaluation.launch"
export DR_CURRENT_PARAMS_FILE=${DR_LOCAL_S3_EVAL_PARAMS_FILE}

if [ ${DR_ROBOMAKER_MOUNT_LOGS,,} = "true" ]; then
  COMPOSE_FILES="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DR_DIR/docker/docker-compose-mount.yml"
  export DR_MOUNT_DIR="$DR_DIR/data/logs/robomaker/$DR_LOCAL_S3_MODEL_PREFIX"
  mkdir -p $DR_MOUNT_DIR
else
  COMPOSE_FILES="$DR_EVAL_COMPOSE_FILE"
fi

echo "Creating Robomaker configuration in $S3_PATH/$DR_CURRENT_PARAMS_FILE"
python3 $DR_DIR/scripts/evaluation/prepare-config.py

# Check if we are using Host X -- ensure variables are populated
if [[ "${DR_HOST_X,,}" == "true" ]]; then
  if [[ -n "$DR_DISPLAY" ]]; then
    ROBO_DISPLAY=$DR_DISPLAY
  else
    ROBO_DISPLAY=$DISPLAY
  fi

  if ! DISPLAY=$ROBO_DISPLAY timeout 1s xset q &>/dev/null; then
    echo "No X Server running on display $ROBO_DISPLAY. Exiting"
    exit 0
  fi

  if [[ -z "$XAUTHORITY" ]]; then
    export XAUTHORITY=~/.Xauthority
    if [[ ! -f "$XAUTHORITY" ]]; then
      echo "No XAUTHORITY defined. .Xauthority does not exist. Stopping."
      exit 0
    fi
  fi
fi

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
  DISPLAY=$ROBO_DISPLAY docker stack deploy $COMPOSE_FILES $STACK_NAME
else
  DISPLAY=$ROBO_DISPLAY docker compose $COMPOSE_FILES -p $STACK_NAME up -d
fi

# Request to be quiet. Quitting here.
if [ -n "$OPT_QUIET" ]; then
  exit 0
fi

# Trigger requested log-file
dr-logs-robomaker -w 15 -e
