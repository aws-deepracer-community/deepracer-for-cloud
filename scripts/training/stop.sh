#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname ${SCRIPT}`


docker-compose -f "$SCRIPTPATH/../../docker/docker-compose.yml" down

docker stop $(docker ps | awk ' /sagemaker/ { print $1 }')
docker rm $(docker ps -a | awk ' /sagemaker/ { print $1 }')