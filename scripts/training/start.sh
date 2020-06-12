#!/usr/bin/env bash

source $DR_DIR/bin/scripts_wrapper.sh

usage(){
	echo "Usage: $0 [-w]"
  echo "       -w        Wipes the target AWS DeepRacer model structure before upload."
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

while getopts ":wh" opt; do
case $opt in
w) OPT_WIPE="WIPE"
;;
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

# Ensure Sagemaker's folder is there
sudo mkdir -p /tmp/sagemaker

#Check if files are available
S3_PATH="s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX"

S3_FILES=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 ls ${S3_PATH} | wc -l)
if [[ $S3_FILES > 0 ]];
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

if [ "$DR_WORKERS" -gt 1 ]; then
  echo "Starting $DR_WORKERS workers"
  mkdir -p $DR_DIR/tmp/comms.$DR_RUN_ID
  rm -rf $DR_DIR/tmp/comms.$DR_RUN_ID/*
  COMPOSE_FILES="$COMPOSE_FILES $DR_DOCKER_FILE_SEP $DR_DIR/docker/docker-compose-robomaker-multi.yml"
  export ROBOMAKER_COMMAND="./run.sh multi distributed_training.launch"
else
  export ROBOMAKER_COMMAND="./run.sh run distributed_training.launch"
fi

export DR_CURRENT_PARAMS_FILE=${DR_LOCAL_S3_TRAINING_PARAMS_FILE}

echo "Creating Robomaker configuration in $S3_PATH/$DR_LOCAL_S3_TRAINING_PARAMS_FILE"
python3 prepare-config.py

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  docker stack deploy $COMPOSE_FILES $STACK_NAME
else
  docker-compose $COMPOSE_FILES -p $STACK_NAME --log-level ERROR up -d --scale robomaker=$DR_WORKERS
fi

echo 'Waiting for containers to start up...'

#sleep for 20 seconds to allow the containers to start
sleep 15

if xhost >& /dev/null;
then
  echo "Display exists, using gnome-terminal for logs and starting vncviewer."
  if ! [ -x "$(command -v gnome-terminal)" ]; 
  then
    echo 'Error: skip showing sagemaker logs because gnome-terminal is not installed.  This is normal if you are on a different OS to Ubuntu.'
  else	
    echo 'attempting to pull up sagemaker logs...'
    gnome-terminal -x sh -c "!!; docker logs -f $(docker ps -a | awk ' /sagemaker/ { print $1 }')"
  fi

  if ! [ -x "$(command -v gnome-terminal)" ]; 
  then
    if ! [ -x "$(command -v vncviewer)" ]; 
    then
      echo 'Error: vncviewer is not present on the PATH.  Make sure you install it and add it to the PATH.'
    else	
      echo 'attempting to open vnc viewer...'
      vncviewer localhost:8080
    fi
  else	
    echo 'attempting to open vnc viewer...'
    gnome-terminal -x sh -c "!!; vncviewer localhost:8080"
  fi
else
  echo "No display. Falling back to CLI mode."
  dr-logs-sagemaker
fi
