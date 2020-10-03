#!/usr/bin/env bash

source $DR_DIR/bin/scripts_wrapper.sh

usage(){
	echo "Usage: $0 [-q]"
  echo "       -q        Quiet - does not start log tracing."
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

while getopts ":q" opt; do
case $opt in
q) OPT_QUIET="QUIET"
;;
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done


# set evaluation specific environment variables
S3_PATH="s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX"
STACK_NAME="deepracer-eval-$DR_RUN_ID"

export ROBOMAKER_COMMAND="./run.sh run evaluation.launch"
export DR_CURRENT_PARAMS_FILE=${DR_LOCAL_S3_EVAL_PARAMS_FILE}

if [ ${DR_ROBOMAKER_MOUNT_LOGS,,} = "true" ];
then
  COMPOSE_FILES="$DR_EVAL_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DR_DIR/docker/docker-compose-mount.yml"
  export DR_MOUNT_DIR="$DR_DIR/data/logs/robomaker/$DR_LOCAL_S3_MODEL_PREFIX"
  mkdir -p $DR_MOUNT_DIR
else
  COMPOSE_FILES="$DR_EVAL_COMPOSE_FILE"
fi

echo "Creating Robomaker configuration in $S3_PATH/$DR_CURRENT_PARAMS_FILE"
python3 $DR_DIR/scripts/evaluation/prepare-config.py

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  docker stack deploy $COMPOSE_FILES $STACK_NAME
else
  docker-compose $COMPOSE_FILES --log-level ERROR -p $STACK_NAME up -d
fi

# Request to be quiet. Quitting here.
if [ -n "$OPT_QUIET" ]; then
  exit 0
fi

# Trigger requested log-file
dr-logs-robomaker -w 15 -e

