#!/usr/bin/env bash

STACK_NAME="deepracer-eval-$DR_RUN_ID"
RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

docker stack rm $STACK_NAME