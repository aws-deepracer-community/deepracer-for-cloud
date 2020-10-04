#!/usr/bin/python3

import boto3
import sys
import os 
import time
import json
import io
import yaml

def str2bool(v):
  return v.lower() in ("yes", "true", "t", "1")

config = {}

# Basic configuration; common for all racers

tournament_s3_prefix = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'tournament')
tournament_s3_bucket = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')

config['AWS_REGION'] = os.environ.get('DR_AWS_APP_REGION', 'us-east-1')
config['JOB_TYPE'] = 'EVALUATION'
config['ROBOMAKER_SIMULATION_JOB_ACCOUNT_ID'] = os.environ.get('', 'Dummy')
config['RACE_TYPE'] = 'HEAD_TO_MODEL'
config['WORLD_NAME'] = os.environ.get('DR_WORLD_NAME', 'LGSWide')
config['NUMBER_OF_TRIALS'] = os.environ.get('DR_EVAL_NUMBER_OF_TRIALS', '5')

is_continous = str2bool(os.environ.get('DR_EVAL_IS_CONTINUOUS', 'False'))
if is_continous:
    config['NUMBER_OF_RESETS'] = '10000'
    config['IS_CONTINUOUS'] = os.environ.get('DR_EVAL_IS_CONTINUOUS', 'True')

config['OFF_TRACK_PENALTY'] = os.environ.get('DR_EVAL_OFF_TRACK_PENALTY', '5.0')

# Tournament bucket for logs, and overall storage
tournament_config = os.environ.get('DR_LOCAL_S3_TOURNAMENT_JSON_FILE', 'tournament.json')
print("Reading in tournament file {}".format(tournament_config))

config['RACER_NAME'] = []
config['DISPLAY_NAME'] = []
config['MODEL_S3_PREFIX'] = []
config['MODEL_S3_BUCKET'] = []
config['SIMTRACE_S3_PREFIX'] = []
config['SIMTRACE_S3_BUCKET'] = []
config['KINESIS_VIDEO_STREAM_NAME'] = []
config['METRICS_S3_BUCKET'] = []
config['METRICS_S3_PREFIX'] = []
config['MP4_S3_BUCKET'] = []
config['MP4_S3_OBJECT_PREFIX'] = []
config['MODEL_METADATA_FILE_S3_KEY'] = []

with open(tournament_config) as tournament_config_json:
    tournament_config_data = json.load(tournament_config_json)
    for r in tournament_config_data['racers']:
        config['RACER_NAME'].append(r['racer_name'])
        config['DISPLAY_NAME'].append(r['racer_name'])
        config['MODEL_S3_PREFIX'].append(r['s3_prefix'])
        config['MODEL_S3_BUCKET'].append(r['s3_bucket'])
        config['MODEL_METADATA_FILE_S3_KEY'].append("{}/model/model_metadata.json".format(r['s3_prefix']))
        config['KINESIS_VIDEO_STREAM_NAME'].append("None")
        config['SIMTRACE_S3_BUCKET'].append(tournament_s3_bucket)
        config['SIMTRACE_S3_PREFIX'].append("{}/{}/simtrace/".format(tournament_s3_prefix, r['racer_name']))
        config['MP4_S3_BUCKET'].append(tournament_s3_bucket)
        config['MP4_S3_OBJECT_PREFIX'].append("{}/{}/mp4/".format(tournament_s3_prefix, r['racer_name']))
        config['METRICS_S3_BUCKET'].append(tournament_s3_bucket)
        config['METRICS_S3_PREFIX'].append("{}/{}/metrics/".format(tournament_s3_prefix, r['racer_name']))

# S3 Setup / write and upload file
s3_endpoint_url = os.environ.get('DR_LOCAL_S3_ENDPOINT_URL', None)
s3_region = config['AWS_REGION']
s3_bucket = tournament_s3_bucket
s3_prefix = tournament_s3_prefix
s3_mode = os.environ.get('DR_LOCAL_S3_AUTH_MODE','profile')
if s3_mode == 'profile':
    s3_profile = os.environ.get('DR_LOCAL_S3_PROFILE', 'default')
else: # mode is 'role'
    s3_profile = None
s3_yaml_name = os.environ.get('DR_LOCAL_S3_TOURNAMENT_PARAMS_FILE', 'tournament-params.yaml')
yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))

session = boto3.session.Session(profile_name=s3_profile)
s3_client = session.client('s3', region_name=s3_region, endpoint_url=s3_endpoint_url)

yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))
local_yaml_path = os.path.abspath(os.path.join(os.environ.get('DR_DIR'),'tmp', 'tournament-params-' + str(round(time.time())) + '.yaml'))

with open(local_yaml_path, 'w') as yaml_file:
    yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)

s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)
