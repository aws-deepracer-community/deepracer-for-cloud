#!/usr/bin/env bash

export ROBOMAKER_COMMAND="./run.sh build distributed_training.launch"
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
