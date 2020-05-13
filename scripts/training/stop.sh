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

docker stack rm $STACK_NAME