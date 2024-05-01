#!/bin/bash

COMPOSE_FILES=./docker/docker-compose-influx.yml

docker-compose -f $COMPOSE_FILES -p influx down