#!/usr/bin/env bash

source $DR_DIR/bin/scripts_wrapper.sh

usage() {
  echo "Usage: $0 [-q]"
  echo "       -q        Quiet - does not start log tracing."
  exit 1
}

trap ctrl_c INT

function ctrl_c() {
  echo "Requested to stop."
  exit 1
}

while getopts ":qh" opt; do
  case $opt in
  q)
    OPT_QUIET="QUIET"
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

## Check if WSL2
if [[ -f /proc/version ]] && grep -qi Microsoft /proc/version && grep -q "WSL2" /proc/version; then
    IS_WSL2="yes"
fi

# set virtual-racing specific environment variables
STACK_NAME="deepracer-virtual-$DR_RUN_ID"
STACK_CONTAINERS=$(docker stack ps $STACK_NAME 2>/dev/null | wc -l)
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
  if [[ "$STACK_CONTAINERS" -gt 1 ]]; then
    echo "ERROR: Processes running in stack $STACK_NAME. Stop virtual racing with dr-stop-virtual."
    exit 1
  fi
fi

# Ensure Sagemaker's folder is there
_dr_ensure_sagemaker_dir

# Resolve the SQS queue URL that drives the worker loop.
if [[ "${DR_CLOUD,,}" == "aws" ]]; then
  echo "Ensuring AWS SQS FIFO queue $DR_VIRTUAL_SQS_QUEUE_NAME exists."
  DR_VIRTUAL_SQS_QUEUE_URL=$(aws sqs create-queue \
    --queue-name "$DR_VIRTUAL_SQS_QUEUE_NAME" \
    --attributes FifoQueue=true,ContentBasedDeduplication=false \
    --region "$DR_AWS_APP_REGION" \
    --query QueueUrl --output text)
  if [[ -z "$DR_VIRTUAL_SQS_QUEUE_URL" ]]; then
    echo "ERROR: Failed to create or resolve SQS queue $DR_VIRTUAL_SQS_QUEUE_NAME."
    exit 1
  fi
else
  # ElasticMQ resolves the queue by the last path segment; the account id is a
  # fixed placeholder. The queue itself is predefined in docker/files/elasticmq.conf.
  DR_VIRTUAL_SQS_QUEUE_URL="${DR_VIRTUAL_SQS_ENDPOINT_URL}/000000000000/${DR_VIRTUAL_SQS_QUEUE_NAME}"
fi
export DR_VIRTUAL_SQS_QUEUE_URL

echo "Virtual racing host for s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX starting."
echo "Using image ${DR_SIMAPP_SOURCE}:${DR_SIMAPP_VERSION}"
echo "Queue: $DR_VIRTUAL_SQS_QUEUE_URL"
echo ""

S3_PATH="s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX"

export ROBOMAKER_COMMAND="/opt/ml/code/run.sh run virtual_event.launch.py"
export DR_CURRENT_PARAMS_FILE=${DR_LOCAL_S3_VIRTUAL_PARAMS_FILE:-virtual_event_params.yaml}

if [ ${DR_ROBOMAKER_MOUNT_LOGS,,} = "true" ]; then
  COMPOSE_FILES="$DR_VIRTUAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DR_DIR/docker/docker-compose-mount.yml"
  export DR_MOUNT_DIR="$DR_DIR/data/logs/robomaker/$DR_LOCAL_S3_MODEL_PREFIX"
  mkdir -p $DR_MOUNT_DIR
else
  COMPOSE_FILES="$DR_VIRTUAL_COMPOSE_FILE"
fi

echo "Creating Virtual Event configuration in $S3_PATH/$DR_CURRENT_PARAMS_FILE"
python3 $DR_DIR/scripts/virtual/prepare-config.py

# Check if we are using Host X -- ensure variables are populated
if [[ "${DR_HOST_X,,}" == "true" ]]; then
  if [[ -n "$DR_DISPLAY" ]]; then
    ROBO_DISPLAY=$DR_DISPLAY
  else
    ROBO_DISPLAY=$DISPLAY
  fi

  if ! DISPLAY=$ROBO_DISPLAY timeout 1s xset q &>/dev/null; then
    echo "No X Server running on display $ROBO_DISPLAY. Exiting"
    exit 1
  fi

  if [[ -z "$XAUTHORITY" && "$IS_WSL2" != "yes" ]]; then
    export XAUTHORITY=~/.Xauthority
    if [[ ! -f "$XAUTHORITY" ]]; then
      echo "No XAUTHORITY defined. .Xauthority does not exist. Stopping."
      exit 1
    fi
  fi
fi

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then

  if [ "$DR_DOCKER_MAJOR_VERSION" -gt 24 ]; then
    DETACH_FLAG="--detach=true"
  fi

  DISPLAY=$ROBO_DISPLAY docker stack deploy $COMPOSE_FILES $DETACH_FLAG $STACK_NAME
else
  DISPLAY=$ROBO_DISPLAY docker compose $COMPOSE_FILES -p $STACK_NAME up -d
fi

# Request to be quiet. Quitting here.
if [ -n "$OPT_QUIET" ]; then
  exit 0
fi

echo "Virtual racing host started. Enqueue racers with: dr-addracer-virtual"
echo "Tail the host with: dr-logs-robomaker -v"
