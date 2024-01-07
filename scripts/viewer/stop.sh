#!/usr/bin/env bash

STACK_NAME="deepracer-$DR_RUN_ID-viewer"
COMPOSE_FILES=$DR_DIR/docker/docker-compose-webviewer.yml

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
    docker stack rm $STACK_NAME
else
    docker compose -f $COMPOSE_FILES -p $STACK_NAME --log-level ERROR down
fi