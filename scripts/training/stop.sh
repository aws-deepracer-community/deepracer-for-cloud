#!/usr/bin/env bash
STACK_NAME="deepracer-$DR_RUN_ID"
RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

SAGEMAKER_CONTAINERS=$(docker ps | awk ' /simapp/ { print $1 } ' | xargs)

if [[ -n "$SAGEMAKER_CONTAINERS" ]]; then
    for CONTAINER in $SAGEMAKER_CONTAINERS; do
        CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
        CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)-(algo-(.)-(.*))/; print $1')
        COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)-(algo-(.)-(.*))/; print $2')

        if [[ -n "$COMPOSE_SERVICE_NAME" ]]; then
            COMPOSE_FILES=$(sudo find /tmp/sagemaker -name docker-compose.yaml -exec grep -l "$COMPOSE_SERVICE_NAME" {} +)
            for COMPOSE_FILE in $COMPOSE_FILES; do
                if sudo grep -q "RUN_ID=${DR_RUN_ID}" $COMPOSE_FILE && sudo grep -q "${RUN_NAME}" $COMPOSE_FILE; then
                    echo Found Sagemaker as $CONTAINER_NAME

                    # Check if Docker version is greater than 24
                    if [ "$DOCKER_MAJOR_VERSION" -gt 24 ]; then
                        # Remove version tag from docker-compose.yaml
                        sed -i '/^version:/d' docker-compose.yaml
                    fi

                    sudo docker compose -f $COMPOSE_FILE stop $COMPOSE_SERVICE_NAME
                    docker container rm $CONTAINER -v >/dev/null
                fi
            done
        fi
    done
fi

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    docker stack rm $STACK_NAME
else
    COMPOSE_FILES=$(echo ${DR_TRAIN_COMPOSE_FILE} | cut -f1-2 -d\ )
    export DR_CURRENT_PARAMS_FILE=""
    docker compose $COMPOSE_FILES -p $STACK_NAME down
fi
