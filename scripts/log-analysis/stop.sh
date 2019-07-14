#!/usr/bin/env bash

docker stop $(docker ps | awk ' /analysis/ { print $1 }')
