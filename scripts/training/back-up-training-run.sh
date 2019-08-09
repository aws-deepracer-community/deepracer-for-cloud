#!/usr/bin/env bash

BACKUP_LOC=/media/aschu/storage/deepracer-training/backup
FILENAME=$(date +%Y-%m-%d_%H-%M-%S)
tar -czvf ${FILENAME}.tar.gz ../../docker/volumes/minio/bucket/rl-deepracer-sagemaker/*
mv ${FILENAME}.tar.gz $BACKUP_LOC