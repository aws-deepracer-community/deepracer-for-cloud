#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

rm -rf ${SCRIPTPATH}/../../docker/volumes/minio/bucket/rl-deepracer-pretrained
mv ${SCRIPTPATH}/../../docker/volumes/minio/bucket/rl-deepracer-sagemaker ${SCRIPTPATH}/../../docker/volumes/minio/bucket/rl-deepracer-pretrained