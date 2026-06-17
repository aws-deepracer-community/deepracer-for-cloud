#!/usr/bin/python3

#
# Builds the virtual_event race YAML and uploads it to S3 / MinIO.
#
# The virtual_event worker (simapp) reads this YAML via WorldConfig.get_param.
# Mandatory keys are SQS_QUEUE_URL and KINESIS_WEBRTC_SIGNALING_CHANNEL_NAME;
# the remaining keys configure the race itself. Racer profiles (model + output
# locations) are NOT part of this YAML - they arrive as SQS messages enqueued
# via dr-addracer-virtual.
#

import boto3
import os
import time
import yaml


def str2bool(v):
    return v.lower() in ("yes", "true", "t", "1")


config = {}

# Region
config['AWS_REGION'] = os.environ.get('DR_AWS_APP_REGION', 'us-east-1')

# Queue that drives the worker loop. For local/remote/azure this points at the
# in-stack ElasticMQ service; for AWS it is the real SQS FIFO queue URL.
config['SQS_QUEUE_URL'] = os.environ.get('DR_VIRTUAL_SQS_QUEUE_URL', '')

# KVS WebRTC signaling channel is a mandatory YAML key even when video is off.
# A dummy value is used when KVS is disabled (MVP default).
config['KINESIS_WEBRTC_SIGNALING_CHANNEL_NAME'] = \
    os.environ.get('DR_VIRTUAL_KVS_WEBRTC_CHANNEL', 'dummy-virtual-channel')

# Race parameters
config['RACE_TYPE'] = os.environ.get('DR_VIRTUAL_RACE_TYPE', 'TIME_TRIAL')
config['RACE_DURATION'] = os.environ.get('DR_VIRTUAL_RACE_DURATION', '180')
config['NUMBER_OF_TRIALS'] = os.environ.get('DR_VIRTUAL_NUMBER_OF_TRIALS', '3')
config['NUMBER_OF_RESETS'] = os.environ.get('DR_VIRTUAL_NUMBER_OF_RESETS', '0')
config['IS_CONTINUOUS'] = os.environ.get('DR_VIRTUAL_IS_CONTINUOUS', 'False')
config['PENALTY_SECONDS'] = os.environ.get('DR_VIRTUAL_PENALTY_SECONDS', '2.0')
config['OFF_TRACK_PENALTY'] = os.environ.get('DR_VIRTUAL_OFF_TRACK_PENALTY', '2.0')
config['COLLISION_PENALTY'] = os.environ.get('DR_VIRTUAL_COLLISION_PENALTY', '5.0')
config['NUM_SECTORS'] = os.environ.get('DR_VIRTUAL_NUM_SECTORS', '3')
config['START_POS_OFFSET'] = os.environ.get('DR_VIRTUAL_START_POS_OFFSET', '0.0')
config['CHANGE_START_POSITION'] = os.environ.get('DR_VIRTUAL_CHANGE_START_POSITION', 'False')
config['ALTERNATE_DRIVING_DIRECTION'] = os.environ.get('DR_VIRTUAL_ALTERNATE_DRIVING_DIRECTION', 'False')

# Pass the S3 endpoint through for components that read it from the race config.
s3_container_endpoint_url = os.environ.get('DR_MINIO_URL', None)
if s3_container_endpoint_url is not None:
    config['S3_ENDPOINT_URL'] = s3_container_endpoint_url

# World/track name. WorldConfig.get_param("WORLD_NAME", "default_world") in TrackData
# reads this from the YAML, so it must be present or the wrong routes file is loaded.
config['WORLD_NAME'] = os.environ.get('DR_WORLD_NAME', '')

# S3 Setup / write and upload file
s3_local_endpoint_url = os.environ.get('DR_LOCAL_S3_ENDPOINT_URL', None)
s3_region = config['AWS_REGION']
s3_bucket = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
s3_prefix = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
s3_mode = os.environ.get('DR_LOCAL_S3_AUTH_MODE', 'profile')
if s3_mode == 'profile':
    s3_profile = os.environ.get('DR_LOCAL_S3_PROFILE', 'default')
else:  # mode is 'role'
    s3_profile = None
s3_yaml_name = os.environ.get('DR_LOCAL_S3_VIRTUAL_PARAMS_FILE', 'virtual_event_params.yaml')

session = boto3.session.Session(profile_name=s3_profile)
s3_client = session.client('s3', region_name=s3_region, endpoint_url=s3_local_endpoint_url)

yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))
local_yaml_path = os.path.abspath(
    os.path.join(os.environ.get('DR_DIR'), 'tmp', 'virtual-params-' + str(round(time.time())) + '.yaml'))

with open(local_yaml_path, 'w') as yaml_file:
    yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)

s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)
