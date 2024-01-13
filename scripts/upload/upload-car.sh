#!/bin/bash

usage() {
    echo "Usage: $0 [-L] [-f]"
    echo "       -f        Force. Do not ask for confirmation."
    echo "       -L        Upload model to the local S3 bucket."
    exit 1
}

trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

while getopts ":Lf" opt; do
    case $opt in
    L)
        OPT_LOCAL="Local"
        ;;
    f)
        OPT_FORCE="force"
        ;;
    h)
        usage
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        usage
        ;;
    esac
done

# This script creates the tar.gz file necessary to operate inside a deepracer physical car
# The file is created directly from within the sagemaker container, using the most recent checkpoint

# Find name of sagemaker container
SAGEMAKER_CONTAINERS=$(docker ps | awk ' /sagemaker/ { print $1 } ' | xargs)
if [[ -n $SAGEMAKER_CONTAINERS ]]; then
    for CONTAINER in $SAGEMAKER_CONTAINERS; do
        CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
        CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $1')
        echo "Found Sagemaker container: $CONTAINER_NAME"
    done
fi

#create tmp directory if it doesnt already exit
mkdir -p $DR_DIR/tmp/car_upload
cd $DR_DIR/tmp/car_upload
#ensure directory is empty
rm -r $DR_DIR/tmp/car_upload/*
#The files we want are located inside the sagemaker container at /opt/ml/model.  Copy them to the tmp directory
docker cp $CONTAINER_NAME:/opt/ml/model $DR_DIR/tmp/car_upload
cd $DR_DIR/tmp/car_upload/model
#create a tar.gz file containing all of these files
tar -czvf carfile.tar.gz *

# Upload files
if [[ -z "${OPT_FORCE}" ]]; then
    if [[ -n "${OPT_LOCAL}" ]]; then
        echo "Ready to upload car model to local s3://${DR_LOCAL_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}."
    else
        echo "Ready to upload car model to remote s3://${DR_UPLOAD_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}."
    fi
    read -r -p "Are you sure? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

#upload to s3
if [[ -n "${OPT_LOCAL}" ]]; then
    aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp carfile.tar.gz s3://${DR_LOCAL_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}/carfile.tar.gz
else
    aws ${DR_UPLOAD_PROFILE} s3 cp carfile.tar.gz s3://${DR_UPLOAD_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}/carfile.tar.gz
fi
