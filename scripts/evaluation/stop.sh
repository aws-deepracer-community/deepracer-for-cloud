#!/usr/bin/env bash

docker-compose down

docker stop $(docker ps | awk ' /sagemaker/ { print $1 }')
docker rm $(docker ps -a | awk ' /sagemaker/ { print $1 }')
