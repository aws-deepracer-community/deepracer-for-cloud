#!/usr/bin/env bash

nvidia-docker run --rm -it -p "8888:8888" \
-v `pwd`/../../docker/volumes/log-analysis:/workspace/venv/data \
-v `pwd`/../../docker/volumes/robo/checkpoint/log:/workspace/venv/logs \
 aschu/log-analysis
