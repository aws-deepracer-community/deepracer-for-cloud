#!/bin/bash

# This script creates the tar.gz file necessary to operate inside a deepracer physical car
# The file is created directly from within the sagemaker container, using the most recent checkpoint

# Find name of sagemaker container
SAGEMAKER_CONTAINERS=$(docker ps | awk ' /sagemaker/ { print $1 } '| xargs )
if [[ -n $SAGEMAKER_CONTAINERS ]];
then
    for CONTAINER in $SAGEMAKER_CONTAINERS; do
        CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
        CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $1')
        echo $CONTAINER_NAME
    done
fi

#create tmp directory if it doesnt already exit
mkdir -p "$DR_DIR/tmp/car_upload"
cd "$DR_DIR/tmp/car_upload"
#ensure directory is empty
rm -r "$DR_DIR/tmp/car_upload/"*
#The files we want are located inside the sagemaker container at /opt/ml/model.  Copy them to the tmp directory
docker cp $CONTAINER_NAME:/opt/ml/model "$DR_DIR/tmp/car_upload"
cd "$DR_DIR/tmp/car_upload/model"
#create a tar.gz file containing all of these files
tar -czvf carfile.tar.gz *

#upload to s3
aws ${DR_UPLOAD_PROFILE} s3 cp carfile.tar.gz "s3://${DR_UPLOAD_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}/carfile.tar.gz"

