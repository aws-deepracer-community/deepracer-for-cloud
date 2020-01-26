#!/usr/bin/env bash

docker-compose down

SAGEMAKER=$(docker ps | awk ' /sagemaker/ { print $1 }')
if [[ -n $SAGEMAKER ]];
then
    docker stop $(docker ps | awk ' /sagemaker/ { print $1 }')
    docker rm $(docker ps -a | awk ' /sagemaker/ { print $1 }')
fi