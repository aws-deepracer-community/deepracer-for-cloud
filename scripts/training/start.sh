#!/usr/bin/env bash

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

echo "Creating Robomaker configuration in $S3_PATH/training_params.yaml"
python3 prepare-config.py

export ROBOMAKER_COMMAND="./run.sh build distributed_training.launch"
#export COMPOSE_FILE=$DR_COMPOSE_FILE
docker-compose $DR_COMPOSE_FILE up -d
echo 'Waiting for containers to start up...'

#sleep for 20 seconds to allow the containers to start
sleep 5

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
  docker logs -f $(docker ps | awk ' /sagemaker/ { print $1 }')
fi
