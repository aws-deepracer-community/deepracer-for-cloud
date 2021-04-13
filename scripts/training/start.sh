#!/usr/bin/env bash

source $DR_DIR/bin/scripts_wrapper.sh

usage(){
	echo "Usage: $0 [-w] [-q | -s | -r [n] | -a ]"
  echo "       -w        Wipes the target AWS DeepRacer model structure before upload."
  echo "       -q        Do not output / follow a log when starting."
  echo "       -a        Follow all Sagemaker and Robomaker logs."
  echo "       -s        Follow Sagemaker logs (default)."
  echo "       -r [n]    Follow Robomaker logs for worker n (default worker 0 / replica 1)."
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

OPT_DISPLAY="SAGEMAKER"

while getopts ":whqsar:" opt; do
case $opt in
w) OPT_WIPE="WIPE"
;;
q) OPT_QUIET="QUIET"
;;
s) OPT_DISPLAY="SAGEMAKER"
;;
a) OPT_DISPLAY="ALL"
;;
r)  # Check if value is in numeric format.
    OPT_DISPLAY="ROBOMAKER"
    if [[ $OPTARG =~ ^[0-9]+$ ]]; then
        OPT_ROBOMAKER=$OPTARG
    else
        OPT_ROBOMAKER=0
        ((OPTIND--))
    fi
;;  
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

# Ensure Sagemaker's folder is there
if [ ! -d /tmp/sagemaker ]; then
  sudo mkdir -p /tmp/sagemaker
  sudo chmod -R g+w /tmp/sagemaker
fi

#Check if files are available
S3_PATH="s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX"

S3_FILES=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 ls ${S3_PATH} | wc -l)
if [[ "$S3_FILES" -gt 0 ]];
then
  if [[ -z $OPT_WIPE ]];
  then
    echo "Selected path $S3_PATH exists. Delete it, or use -w option. Exiting."
    exit 1
  else
    echo "Wiping path $S3_PATH."
    aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 rm --recursive ${S3_PATH}
  fi
fi

# Base compose file
if [ ${DR_ROBOMAKER_MOUNT_LOGS,,} = "true" ];
then
  COMPOSE_FILES="$DR_TRAIN_COMPOSE_FILE $DR_DOCKER_FILE_SEP $DR_DIR/docker/docker-compose-mount.yml"
  export DR_MOUNT_DIR="$DR_DIR/data/logs/robomaker/$DR_LOCAL_S3_MODEL_PREFIX"
  mkdir -p $DR_MOUNT_DIR
else
  COMPOSE_FILES="$DR_TRAIN_COMPOSE_FILE"
fi

# set evaluation specific environment variables
STACK_NAME="deepracer-$DR_RUN_ID"

export DR_CURRENT_PARAMS_FILE=${DR_LOCAL_S3_TRAINING_PARAMS_FILE}

WORKER_CONFIG=$(python3 $DR_DIR/scripts/training/prepare-config.py)

if [ "$DR_WORKERS" -gt 1 ]; then
  echo "Starting $DR_WORKERS workers"

  if [[ "${DR_DOCKER_STYLE,,}" != "swarm" ]];
  then
    mkdir -p $DR_DIR/tmp/comms.$DR_RUN_ID
    rm -rf $DR_DIR/tmp/comms.$DR_RUN_ID/*
    COMPOSE_FILES="$COMPOSE_FILES $DR_DOCKER_FILE_SEP $DR_DIR/docker/docker-compose-robomaker-multi.yml"
  fi

  if [ "$DR_TRAIN_MULTI_CONFIG" == "True" ]; then
    export MULTI_CONFIG=$WORKER_CONFIG
    echo "Multi-config training, creating multiple Robomaker configurations in $S3_PATH"  
  else
    echo "Creating Robomaker configuration in $S3_PATH/$DR_LOCAL_S3_TRAINING_PARAMS_FILE" 
  fi
  export ROBOMAKER_COMMAND="./run.sh multi distributed_training.launch"

else
  export ROBOMAKER_COMMAND="./run.sh run distributed_training.launch"
  echo "Creating Robomaker configuration in $S3_PATH/$DR_LOCAL_S3_TRAINING_PARAMS_FILE"
fi

# Check if we are using Host X -- ensure variables are populated
if [[ "${DR_HOST_X,,}" == "true" ]];
then
  if [[ -n "$DR_DISPLAY" ]]; then
    DISPLAY_ORIG=$DISPLAY
    export DISPLAY=$DR_DISPLAY
  fi
  if [[ -z "$XAUTHORITY" ]]; then
    export XAUTHORITY=~/.Xauthority
  fi
fi

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  ROBOMAKER_NODES=$(docker node ls --format '{{.ID}}' | xargs docker inspect | jq '.[] | select (.Spec.Labels.Robomaker == "true") | .ID' | wc -l)
  if [[ "$ROBOMAKER_NODES" -eq 0 ]]; 
  then
    echo "ERROR: No Swarm Nodes labelled for placement of Robomaker. Please add Robomaker node."
    echo "       Example: docker node update --label-add Robomaker=true $(docker node inspect self | jq .[0].ID -r)"
    exit 0
  fi

  SAGEMAKER_NODES=$(docker node ls --format '{{.ID}}' | xargs docker inspect | jq '.[] | select (.Spec.Labels.Sagemaker == "true") | .ID' | wc -l)
  if [[ "$SAGEMAKER_NODES" -eq 0 ]]; 
  then
    echo "ERROR: No Swarm Nodes labelled for placement of Sagemaker. Please add Sagemaker node."
    echo "       Example: docker node update --label-add Sagemaker=true $(docker node inspect self | jq .[0].ID -r)"
    exit 0
  fi

  docker stack deploy $COMPOSE_FILES $STACK_NAME
else
  docker-compose $COMPOSE_FILES -p $STACK_NAME --log-level ERROR up -d --scale robomaker=$DR_WORKERS
fi

export DISPLAY=$DISPLAY_ORIG

# Request to be quiet. Quitting here.
if [ -n "$OPT_QUIET" ]; then
  exit 0
fi

# Trigger requested log-file
if [[ "${OPT_DISPLAY,,}" == "all" && -n "${DISPLAY}" && "${DR_HOST_X,,}" == "true" ]]; then
  dr-logs-sagemaker -w 15
  if [ "${DR_WORKERS}" -gt 1 ]; then
    for i in $(seq 1 ${DR_WORKERS})
    do
      dr-logs-robomaker -w 15 -n $i
    done    
  else
    dr-logs-robomaker -w 15
  fi
elif [[ "${OPT_DISPLAY,,}" == "robomaker" ]]; then
  dr-logs-robomaker -w 15 -n $OPT_ROBOMAKER
elif [[ "${OPT_DISPLAY,,}" == "sagemaker" ]]; then
  dr-logs-sagemaker -w 15
fi

