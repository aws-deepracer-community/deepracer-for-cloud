#!/usr/bin/env bash

## this is the default autorun script
## file should run automatically after init.sh completes.
## this script downloads your configured run.env, system.env and any custom container requests

INSTALL_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

## retrieve the s3_location name you sent the instance in user data launch
## assumed to first line of file
S3_LOCATION=$(awk 'NR==1 {print; exit}' $INSTALL_DIR_TEMP/autorun.s3url)

source $INSTALL_DIR_TEMP/bin/activate.sh

## get the updatated run.env and system.env files and any others you stashed in s3
aws s3 sync s3://$S3_LOCATION $INSTALL_DIR_TEMP

## get the right docker containers, if needed
SYSENV="$INSTALL_DIR_TEMP/system.env"
SAGEMAKER_IMAGE=$(cat $SYSENV | grep DR_SAGEMAKER_IMAGE | sed 's/.*=//')
ROBOMAKER_IMAGE=$(cat $SYSENV | grep DR_ROBOMAKER_IMAGE | sed 's/.*=//')

docker pull awsdeepracercommunity/deepracer-sagemaker:$SAGEMAKER_IMAGE
docker pull awsdeepracercommunity/deepracer-robomaker:$ROBOMAKER_IMAGE

dr-reload

date | tee $INSTALL_DIR_TEMP/DONE-AUTORUN

## start training
cd $INSTALL_DIR_TEMP/scripts/training
./start.sh
