#!/usr/bin/env bash

# create directory structure for docker volumes
mkdir -p docker/volumes/minio/bucket/custom_files \
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

# replace the contents of the rl_deepracer_coach_robomaker.py file with the gpu specific version (this is also where you can edit the hyperparameters)
# TODO this file should be genrated from a gui before running training
cat overrides/rl_deepracer_coach_robomaker.py > rl_deepracer_coach_robomaker.py

#set proxys if required
for arg in "$@";
do
    IFS='=' read -ra part <<< "$arg"
    if [ "${part[0]}" == "--http_proxy" ] || [ "${part[0]}" == "--https_proxy" ] || [ "${part[0]}" == "--no_proxy" ]; then
        var=${part[0]:2}=${part[1]}
        envs=$'\n'"${var}${envs}"
        args="${args} --build-arg ${var}"
    fi
done

echo -e "$envs" >> ./docker/.env

# build rl-coach image with latest code from crr0004's repo
docker build ${args} -f ./docker/dockerfiles/rl_coach/Dockerfile -t aschu/rl_coach deepracer/

# copy reward function and model-metadata files to bucket 
cp deepracer/custom_files/* docker/volumes/minio/bucket/custom_files/

# create the network sagemaker-local if it doesn't exit
SAGEMAKER_NW='sagemaker-local'
docker network ls | grep -q $SAGEMAKER_NW
if [ $? -ne 0 ]
then
	  docker network create $SAGEMAKER_NW
fi