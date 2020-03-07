#!/usr/bin/env bash

usage(){
	echo "Usage: $0 [-f] [-k]"
    echo ""
    echo "Command will start training."
    echo "-f        Force deletion of model path. Ask for no confirmations."
    echo "-k        Keep model path"
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

OPT_DELIM='-'

while getopts ":fkh" opt; do
case $opt in

f) OPT_FORCE="True"
;;
k) OPT_KEEP="Keep"
;;
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

export ROBOMAKER_COMMAND="./run.sh build distributed_training.launch"

if [[ -z "${OPT_KEEP}" ]];
then
    MODEL_DIR_S3=$(aws $LOCAL_PROFILE_ENDPOINT_URL s3 ls s3://${LOCAL_S3_BUCKET}/${LOCAL_S3_MODEL_PREFIX} )
    if [[ -n "${MODEL_DIR_S3}" ]];
      then
          echo "The new model's S3 prefix s3://${LOCAL_S3_BUCKET}/${LOCAL_S3_MODEL_PREFIX} exists. Will wipe."
      if [[ -z "${OPT_FORCE}" ]]; 
      then
          read -r -p "Are you sure? [y/N] " response
          if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
          then
              echo "Aborting."
              exit 1
          fi
      fi
      aws $LOCAL_PROFILE_ENDPOINT_URL s3 rm s3://${LOCAL_S3_BUCKET}/${LOCAL_S3_MODEL_PREFIX} --recursive
    fi
fi

docker-compose up -d
echo 'waiting for containers to start up...'

#sleep for 20 seconds to allow the containers to start
sleep 20

if xhost >& /dev/null;
then
  echo "Display exists, using gnome-terminal for logs and starting vncviewer."
  if ! [ -x "$(command -v gnome-terminal)" ]; 
  then
    echo 'Error: skip showing sagemaker logs because gnome-terminal is not installed.  This is normal if you are on a different OS to Ubuntu.'
  else	
    echo 'attempting to pull up sagemaker logs...'
    gnome-terminal -x sh -c "!!; docker logs -f $(docker ps | awk ' /sagemaker/ { print $1 }')"
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
