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
python3 prepare-config.py

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  docker stack deploy $COMPOSE_FILES $STACK_NAME
else
  docker-compose $COMPOSE_FILES --log-level ERROR -p $STACK_NAME up -d
fi

echo 'waiting for containers to start up...'

#sleep for 20 seconds to allow the containers to start
sleep 15

if xhost >& /dev/null;
then
  echo "Display exists, using gnome-terminal for logs and starting vncviewer."

  echo 'attempting to pull up sagemaker logs...'
  gnome-terminal -x sh -c "!!; docker logs -f $(docker ps | awk ' /robomaker/ { print $1 }')"

  echo 'attempting to open vnc viewer...'
  gnome-terminal -x sh -c "!!; vncviewer localhost:8080"
else
  echo "No display. Falling back to CLI mode."
  docker logs -f $(docker ps | awk ' /robomaker/ { print $1 }')
fi
