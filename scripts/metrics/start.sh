#!/bin/bash

COMPOSE_FILES=./docker/docker-compose-metrics.yml

docker-compose -f $COMPOSE_FILES -p deepracer-metrics up -d