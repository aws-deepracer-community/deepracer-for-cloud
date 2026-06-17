#!/usr/bin/env bash

STACK_NAME="deepracer-virtual-$DR_RUN_ID"

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    docker stack rm $STACK_NAME
else
    # Pass the full compose file set so the ElasticMQ service is torn down too.
    export DR_CURRENT_PARAMS_FILE=""
    docker compose $DR_VIRTUAL_COMPOSE_FILE -p $STACK_NAME down
fi
