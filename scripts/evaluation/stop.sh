#!/usr/bin/env bash

docker-compose $DR_COMPOSE_FILE down

SAGEMAKER=$(docker ps | awk ' /sagemaker/ { print $1 }')
if [[ -n $SAGEMAKER ]];
then
    docker stop $(docker ps | awk ' /sagemaker/ { print $1 }')
    docker rm $(docker ps -a | awk ' /sagemaker/ { print $1 }')
fi