#!/usr/bin/env bash

docker-compose -f ../docker/docker-compose.yml up -d


gnome-terminal -x sh -c "!!; docker logs -f $(docker ps | awk ' /sagemaker/ { print $1 }')"

gnome-terminal -x sh -c "!!; vncviewer localhost:8080"

