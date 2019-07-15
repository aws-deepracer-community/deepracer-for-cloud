#!/usr/bin/env bash

rm -rf ../../docker/volumes/minio/bucket/rl-deepracer-sagemaker
rm -rf ../../docker/volumes/robo/checkpoint/checkpoint
mkdir ../../docker/volumes/robo/checkpoint/checkpoint
rm -rf /robo/container/*
rm -rf ../../docker/volumes/robo/checkpoint/log/*
