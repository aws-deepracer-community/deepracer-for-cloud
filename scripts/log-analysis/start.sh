#!/usr/bin/env bash

docker run --rm -d -p "8888:8888" \
-v $DR_DIR/data/logs:/workspace/logs \
-v $DR_DIR/docker/volumes/.aws:/home/ubuntu/.aws \
-v $DR_DIR/data/analysis:/workspace/analysis \
-v $DR_DIR/data/minio:/workspace/minio \
--name deepracer-analysis \
--network sagemaker-local \
 awsdeepracercommunity/deepracer-analysis:$DR_ANALYSIS_IMAGE

docker logs -f deepracer-analysis