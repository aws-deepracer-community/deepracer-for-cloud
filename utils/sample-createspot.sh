#!/usr/bin/env bash

##  This is sample code that will generally show you how to launch a spot instance on aws and leverage the 
##  automation built into deepracer-for-cloud to automatically start training
##  Changes required to work:
##     Input location where your training will take place -- S3_LOCATION
##     Input security group, iam role, and key-name

## First you need to tell the script where in s3 your training will take place
## can be either a bucket at the root level, or a bucket/prefix.  don't include the s3://

S3_LOCATION=<#########>

## extract bucket location
BUCKET=${S3_LOCATION%%/*}

## extract prefix location
if [[ "$S3_LOCATION" == *"/"* ]]
then
  PREFIX=${S3_LOCATION#*/}
else
  PREFIX=""
fi

## Fill these out with your custom information if you want to upload and submit to leaderboard.  not required to run
DR_UPLOAD_S3_PREFIX=########

## set the instance type you want to launch
INSTANCE_TYPE=c5.2xlarge

## if you want to modify additional variables from the default, add them here, then add them to section further below called replace static paramamters.  I've only done World name for now
WORLD_NAME=FS_June2020

## modify this if you want additional robomaker workers
DR_WORKERS=1

## select which images you want to use.  these will be used later for a docker pull
DR_SAGEMAKER_IMAGE=cpu-avx-mkl
DR_ROBOMAKER_IMAGE=cpu-avx2

## check the s3 location for existing training folders
## automatically determine the latest training run (highest number), and set model parameters accordingly
## this script assumes the format rl-deepracer-1, rl-deepracer-2, etc.  you will need to modify if your schema differs

LAST_TRAINING=$(aws s3 ls $S3_LOCATION/rl-deepracer | sort -t - -k 3 -g | tail -n 1 | awk '{print $2}')
## drop trailing slash
LAST_TRAINING=$(echo $LAST_TRAINING | sed 's:/*$::')

CONFIG_FILE="./run.env"
OLD_SYSTEMENV="./system.env"

## incorporate logic from increment.sh, slightly modified to use last training 
OPT_DELIM='-'
## Read in data
CURRENT_RUN_MODEL=$(aws s3 ls $S3_LOCATION/rl-deepracer | sort -t - -k 3 -g | tail -n 1 | awk '{print $2}')
## drop trailing slash
CURRENT_RUN_MODEL=$(echo $LAST_TRAINING | sed 's:/*$::')
## get number at the end
CURRENT_RUN_MODEL_NUM=$(echo "${CURRENT_RUN_MODEL}" | \
                    awk -v DELIM="${OPT_DELIM}" '{ n=split($0,a,DELIM); if (a[n] ~ /[0-9]*/) print a[n]; else print ""; }')

if [ -z $LAST_TRAINING ]
then
    echo No prior training found
    if [[ $PREFIX == "" ]]
    then
      NEW_RUN_MODEL=rl-deepracer-1
    else
      NEW_RUN_MODEL="$PREFIX/rl-deepracer-1"
    fi
    PRETRAINED=False
    CURRENT_RUN_MODEL=$NEW_RUN_MODEL
else

    NEW_RUN_MODEL_NUM=$(echo "${CURRENT_RUN_MODEL_NUM} + 1" | bc )
    PRETRAINED=True

    if [[ $PREFIX == "" ]]
    then
      NEW_RUN_MODEL=$(echo $CURRENT_RUN_MODEL | sed "s/${CURRENT_RUN_MODEL_NUM}\$/${NEW_RUN_MODEL_NUM}/")
    else
      NEW_RUN_MODEL=$(echo $CURRENT_RUN_MODEL | sed "s/${CURRENT_RUN_MODEL_NUM}\$/${NEW_RUN_MODEL_NUM}/")     
      NEW_RUN_MODEL="$PREFIX/$NEW_RUN_MODEL"
      CURRENT_RUN_MODEL="$PREFIX/$CURRENT_RUN_MODEL"
    fi
    echo Last training was $CURRENT_RUN_MODEL so next training is $NEW_RUN_MODEL
fi

if [[ $PREFIX == "" ]]
then
    CUSTOM_FILES_PREFIX="custom_files"
else
    CUSTOM_FILES_PREFIX="$PREFIX/custom_files"
fi

## Replace dynamic parameters in run.env (still local to your directory)
sed -i.bak -re "s:(DR_LOCAL_S3_PRETRAINED_PREFIX=).*$:\1$CURRENT_RUN_MODEL:g; s:(DR_LOCAL_S3_PRETRAINED=).*$:\1$PRETRAINED:g; s:(DR_LOCAL_S3_MODEL_PREFIX=).*$:\1$NEW_RUN_MODEL:g; s:(DR_LOCAL_S3_CUSTOM_FILES_PREFIX=).*$:\1$CUSTOM_FILES_PREFIX:g" "$CONFIG_FILE"
sed -i.bak -re "s/(DR_LOCAL_S3_BUCKET=).*$/\1$BUCKET/g" "$CONFIG_FILE"

## Replace static parameters in run.env (still local to your directory)
sed -i.bak -re "s/(DR_UPLOAD_S3_PREFIX=).*$/\1$DR_UPLOAD_S3_PREFIX/g" "$CONFIG_FILE"
sed -i.bak -re "s/(DR_WORLD_NAME=).*$/\1$WORLD_NAME/g" "$CONFIG_FILE"

## Replace static paramaters in system.env file, including sagemaker and robomaker images (still local to your directory) and the number of DR_workers
sed -i.bak -re "s/(DR_UPLOAD_S3_BUCKET=).*$/\1$DR_UPLOAD_S3_BUCKET/g; s/(DR_SAGEMAKER_IMAGE=).*$/\1$DR_SAGEMAKER_IMAGE/g; s/(DR_ROBOMAKER_IMAGE=).*$/\1$DR_ROBOMAKER_IMAGE/g; s/(DR_WORKERS=).*$/\1$DR_WORKERS/g" "$OLD_SYSTEMENV"

## upload the new run.env and system.env files into your S3 bucket (same s3 location identified earlier)
## files are loaded into the node-config folder/prefix.  You can also upload other files to node config, and they
## will sync to the EC2 instance as part of the autorun script later.  If you add other files, make sure they are 
## in node-config in the same directory structure as DRfc;   example:   s3location/node-config/scripts/training/.start.sh
RUNENV_LOCATION=$S3_LOCATION/node-config/run.env
SYSENV_LOCATION=$S3_LOCATION/node-config/system.env

aws s3 cp ./run.env s3://$RUNENV_LOCATION
aws s3 cp ./system.env s3://$SYSENV_LOCATION

## upload a custom autorun script to S3.  there is a default autorun script in the repo that will be used unless a custom one is specified here instead
#aws s3 cp ./autorun.sh s3://$S3_LOCATION/autorun.sh

## upload custom files -- if you dont want this, comment these lines out
aws s3 cp ./model_metadata.json s3://$S3_LOCATION/custom_files/model_metadata.json
aws s3 cp ./reward_function.py s3://$S3_LOCATION/custom_files/reward_function.py
aws s3 cp ./hyperparameters.json s3://$S3_LOCATION/custom_files/hyperparameters.json

## launch an ec2
## update with your own settings, including key-name, security-group, and iam-instance-profile at a minimum
## user data includes a command to create a .txt file which simply contains the name of the s3 location
## this filename will be used as fundamental input to autorun.sh script run later on that instance
## you need to ensure you have proper IAM permissions to launch this instance

aws ec2 run-instances \
    --image-id ami-085925f297f89fce1 \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name <####keyname####> \
    --security-group-ids sg-<####sgid####> \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={DeleteOnTermination=true,VolumeSize=40}' \
    --iam-instance-profile Arn=arn:aws:iam::<####acct_num####>:instance-profile/<####role_name####> \
    --instance-market-options MarketType=spot \
    --user-data "#!/bin/bash
    su -c 'git clone https://github.com/aws-deepracer-community/deepracer-for-cloud.git && echo "$S3_LOCATION/node-config" > /home/ubuntu/deepracer-for-cloud/autorun.s3url && /home/ubuntu/deepracer-for-cloud/bin/prepare.sh' - ubuntu"
