#!/usr/bin/env bash

STACK_NAME="deepracer-eval-$DR_RUN_ID"
RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    docker stack rm $STACK_NAME
else
    COMPOSE_FILES=$(echo ${DR_EVAL_COMPOSE_FILE} | cut -f1-2 -d\ )
    export DR_CURRENT_PARAMS_FILE=""
    docker compose $COMPOSE_FILES -p $STACK_NAME down
fi
