#!/usr/bin/env bash
source $DR_DIR/bin/scripts_wrapper.sh

STACK_NAME="deepracer-$DR_RUN_ID"
RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

SAGEMAKER_CONTAINERS=$(dr-find-sagemaker)

if [[ -n "$SAGEMAKER_CONTAINERS" ]]; then
    for CONTAINER in $SAGEMAKER_CONTAINERS; do
        CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
        if [[ -n "$CONTAINER_NAME" ]]; then
            echo Found Sagemaker as $CONTAINER_NAME
            if _dr_is_macos; then
                echo "Stopping container $CONTAINER_NAME"
                docker stop $CONTAINER || true
                docker container rm $CONTAINER -v >/dev/null 2>&1 || true
            else
                COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)-(algo-(.)-(.*))/; print $2')
                if [[ -n "$COMPOSE_SERVICE_NAME" ]]; then
                    COMPOSE_FILES=$(_dr_find_sagemaker_compose_files "$COMPOSE_SERVICE_NAME")
                    for COMPOSE_FILE in $COMPOSE_FILES; do
                        if _dr_compose_file_matches_run "$COMPOSE_FILE"; then
                            if [ "$DR_DOCKER_MAJOR_VERSION" -gt 24 ]; then
                                sudo sed -i '/^version:/d' $COMPOSE_FILE
                            fi

                            echo "Stopping service $COMPOSE_SERVICE_NAME"
                            sudo docker compose -f $COMPOSE_FILE stop $COMPOSE_SERVICE_NAME
                            docker container rm $CONTAINER -v >/dev/null 2>&1 || true
                        fi
                    done
                fi
            fi
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
