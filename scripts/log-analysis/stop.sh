#!/usr/bin/env bash

docker stop $(docker ps | awk ' /analysis/ { print $1 }')
#docker rm $(docker ps -a | awk ' /analysis/ { print $1 }')
