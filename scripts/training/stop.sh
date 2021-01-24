#!/usr/bin/env bash

STACK_NAME="deepracer-$DR_RUN_ID"
RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

SAGEMAKER_CONTAINERS=$(docker ps | awk ' /sagemaker/ { print $1 } '| xargs )

if [[ -n $SAGEMAKER_CONTAINERS ]];
then
    for CONTAINER in $SAGEMAKER_CONTAINERS; do
        CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
        CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $1')
        COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $2')
        COMPOSE_FILE=$(sudo find /tmp/sagemaker -name docker-compose.yaml -exec grep -l "$RUN_NAME" {} + | grep $CONTAINER_PREFIX)
        if [[ -n $COMPOSE_FILE ]]; then
            sudo docker-compose -f $COMPOSE_FILE stop $COMPOSE_SERVICE_NAME
            docker container rm $CONTAINER
        fi
    done
fi

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
    docker stack rm $STACK_NAME
else
    COMPOSE_FILES=$(echo ${DR_TRAIN_COMPOSE_FILE} | cut -f1-2 -d\ )
    export DR_CURRENT_PARAMS_FILE=""
    export ROBOMAKER_COMMAND=""
    docker-compose $COMPOSE_FILES -p $STACK_NAME --log-level ERROR down
fi