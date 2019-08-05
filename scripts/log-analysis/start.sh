#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname ${SCRIPT}`

#nvidia-docker run -a STDERR --rm -p "8888:8888" \
#-v ${SCRIPTPATH}/../../docker/volumes/log-analysis:/workspace/venv/data \
#-v ${SCRIPTPATH}/../../docker/volumes/robo/checkpoint/log:/workspace/venv/logs \
# aschu/log-analysis

cd ${SCRIPTPATH}/../../aws-deepracer-workshops/log-analysis
source log-analysis.venv/bin/activate
ipython kernel install --user --name=log-analysis.venv
ln -s ${SCRIPTPATH}/../../docker/volumes/robo/checkpoint/log ${SCRIPTPATH}/../../aws-deepracer-workshops/log-analysis/logs
ln -s ${SCRIPTPATH}/../../docker/volumes/minio/bucket/custom_files/reward.py ${SCRIPTPATH}/../../aws-deepracer-workshops/log-analysis/reward/reward.py
jupyter notebook --no-browser