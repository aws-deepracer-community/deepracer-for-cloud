#!/usr/bin/env bash

CONTAINER_ID=$(docker create --rm -ti -e CUDA_VISIBLE_DEVICES --name cuda-check awsdeepracercommunity/deepracer-robomaker:$DR_ROBOMAKER_IMAGE "python3 cuda-check-tf.py")
docker cp $DR_DIR/utils/cuda-check-tf.py $CONTAINER_ID:/opt/install/
docker start -a $CONTAINER_ID
