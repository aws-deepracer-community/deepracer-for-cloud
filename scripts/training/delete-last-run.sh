#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

rm -rf ${SCRIPTPATH}/../../docker/volumes/minio/bucket/rl-deepracer-sagemaker
rm -rf ${SCRIPTPATH}/../../docker/volumes/robo/checkpoint/checkpoint
mkdir ${SCRIPTPATH}/../../docker/volumes/robo/checkpoint/checkpoint
rm -rf /robo/container/*
rm -rf ${SCRIPTPATH}/../../docker/volumes/robo/checkpoint/log/*
