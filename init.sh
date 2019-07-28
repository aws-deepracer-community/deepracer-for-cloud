#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

# create directory structure for docker volumes
mkdir -p ${SCRIPTPATH}/docker/volumes/minio/bucket/custom_files \
		 ${SCRIPTPATH}/docker/volumes/robo/checkpoint

# create symlink to current user's home .aws directory 
# NOTE: AWS cli must be installed for this to work
# https://docs.aws.amazon.com/cli/latest/userguide/install-linux-al2017.html
ln -s ${SCRIPTPATH}/$(eval echo "~${USER}")/.aws  ${SCRIPTPATH}/docker/volumes/

# grab local training deepracer repo from crr0004 and log analysis repo from vreadcentric
git clone --recurse-submodules https://github.com/ARCC-RACE/deepracer.git

git clone https://github.com/breadcentric/aws-deepracer-workshops.git && cd aws-deepracer-workshops && git checkout enhance-log-analysis && cd ..

ln -s ${SCRIPTPATH}/../../aws-deepracer-workshops/log-analysis  ${SCRIPTPATH}/docker/volumes/log-analysis

# setup symlink to rl-coach config file
ln -s ${SCRIPTPATH}/deepracer/rl_coach/rl_deepracer_coach_robomaker.py ${SCRIPTPATH}/rl_deepracer_coach_robomaker.py

# replace the contents of the rl_deepracer_coach_robomaker.py file with the gpu specific version (this is also where you can edit the hyperparameters)
# TODO this file should be generated from a gui before running training
cat ${SCRIPTPATH}/overrides/rl_deepracer_coach_robomaker.py > ${SCRIPTPATH}/rl_deepracer_coach_robomaker.py

# build rl-coach image with latest code from crr0004's repo
docker build -f ${SCRIPTPATH}/docker/dockerfiles/rl_coach/Dockerfile -t aschu/rl_coach deepracer/

# copy reward function and model-metadata files to bucket 
cp ${SCRIPTPATH}/deepracer/custom_files/* ${SCRIPTPATH}/docker/volumes/minio/bucket/custom_files/