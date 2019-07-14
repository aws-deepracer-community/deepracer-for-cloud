#!/usr/bin/env bash

# create directory structure for docker volumes
mkdir -p docker/volumes/minio/bucket/custom_files \
		 docker/volumes/robo/container \
		 docker/volumes/robo/checkpoint

# create symlink to current user's home .aws directory 
# NOTE: AWS cli must be installed for this to work
# https://docs.aws.amazon.com/cli/latest/userguide/install-linux-al2017.html
ln -s $(eval echo "~${USER}")/.aws  docker/volumes/

# grab local training deepracer repo from crr0004 and log analysis repo from vreadcentric
git clone --recurse-submodules https://github.com/crr0004/deepracer.git

git clone https://github.com/breadcentric/aws-deepracer-workshops.git && cd aws-deepracer-workshops && git checkout enhance-log-analysis && cd ..

ln -s ../../aws-deepracer-workshops/log-analysis  ./docker/volumes/log-analysis

# setup symlink to rl-coach config file
ln -s deepracer/rl_coach/rl_deepracer_coach_robomaker.py rl_deepracer_coach_robomaker.py
#TODO edit rl-coach file with additional hyperparameters using sed or something comparable

# build rl-coach image with latest code from crr0004's repo
docker build -f ./docker/dockerfiles/rl_coach/Dockerfile -t aschu/rl_coach deepracer/

# copy reward function and model-metadata files to bucket 
cp deepracer/custom_files/* docker/volumes/minio/bucket/custom_files/