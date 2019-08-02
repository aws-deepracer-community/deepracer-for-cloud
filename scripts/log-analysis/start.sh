#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname ${SCRIPT}`

#nvidia-docker run -a STDERR --rm -p "8888:8888" \
#-v ${SCRIPTPATH}/../../docker/volumes/log-analysis:/workspace/venv/data \
#-v ${SCRIPTPATH}/../../docker/volumes/robo/checkpoint/log:/workspace/venv/logs \
# aschu/log-analysis

cd ${SCRIPTPATH}/../../aws-deepracer-workshops/log-analysis
jupyter notebook --no-browser