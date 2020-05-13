#!/usr/bin/env bash

source $DR_DIR/bin/scripts_wrapper.sh

usage(){
	echo "Usage: $0 [-w]"
  echo "       -w        Wipes the target AWS DeepRacer model structure before upload."
	exit 1
}

trap ctrl_c INT

# set evaluation specific environment variables
export ROBOMAKER_COMMAND="./run.sh build evaluation.launch"
export DR_CURRENT_PARAMS_FILE=${DR_LOCAL_S3_EVAL_PARAMS_FILE}
S3_PATH="s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_MODEL_PREFIX"

echo "Creating Robomaker configuration in $S3_PATH/$DR_CURRENT_PARAMS_FILE"
python3 prepare-config.py

COMPOSE_FILES=$DR_COMPOSE_FILE
STACK_NAME="deepracer-$DR_RUN_ID"

docker stack deploy $COMPOSE_FILES $STACK_NAME

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
