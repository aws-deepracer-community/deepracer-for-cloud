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
config['AWS_REGION'] = os.environ.get('DR_AWS_APP_REGION', 'us-east-1')
config['CAR_COLOR'] = os.environ.get('DR_CAR_COLOR', 'Red')
config['CAR_NAME'] = os.environ.get('DR_CAR_NAME', 'MyCar')
config['JOB_TYPE'] = 'EVALUATION'
config['KINESIS_VIDEO_STREAM_NAME'] = os.environ.get('DR_KINESIS_STREAM_NAME', 'my-kinesis-stream')
config['METRIC_NAME'] = 'TrainingRewardScore'
config['METRIC_NAMESPACE'] = 'AWSDeepRacer'
config['METRICS_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')

metrics_prefix = os.environ.get('DR_LOCAL_S3_METRICS_PREFIX', None)
if metrics_prefix is not None:
    config['METRICS_S3_OBJECT_KEY'] = '{}/EvaluationMetrics-{}.json'.format(metrics_prefix, str(round(time.time())))
else:
    config['METRICS_S3_OBJECT_KEY'] = 'DeepRacer-Metrics/EvaluationMetrics-{}.json'.format(str(round(time.time())))
    
config['MODEL_S3_PREFIX'] = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
config['MODEL_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
config['NUMBER_OF_TRIALS'] = os.environ.get('DR_EVAL_NUMBER_OF_TRIALS', '5')
config['NUMBER_OF_RESETS'] = os.environ.get('DR_EVAL_NUMBER_OF_RESETS', '0')
config['IS_CONTINUOUS'] = os.environ.get('DR_EVAL_IS_CONTINUOUS', '0')
config['OFF_TRACK_PENALTY'] = os.environ.get('DR_EVAL_OFF_TRACK_PENALTY', '5.0')
config['RACE_TYPE'] = os.environ.get('DR_RACE_TYPE', 'TIME_TRIAL')
config['ROBOMAKER_SIMULATION_JOB_ACCOUNT_ID'] = os.environ.get('', 'Dummy')
config['SIMTRACE_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
config['SIMTRACE_S3_PREFIX'] = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
config['WORLD_NAME'] = os.environ.get('DR_WORLD_NAME', 'LGSWide')

save_mp4 = str2bool(os.environ.get("DR_EVAL_SAVE_MP4", "False"))

if save_mp4:
    config['MP4_S3_BUCKET'] = config['MODEL_S3_BUCKET']
    config['MP4_S3_OBJECT_PREFIX'] = '{}/{}'.format(config['MODEL_S3_PREFIX'],'mp4')

s3_endpoint_url = os.environ.get('DR_LOCAL_S3_ENDPOINT_URL', None)
s3_region = config['AWS_REGION']
s3_bucket = config['MODEL_S3_BUCKET']
s3_prefix = config['MODEL_S3_PREFIX']
s3_mode = os.environ.get('DR_LOCAL_S3_AUTH_MODE','profile')
if s3_mode == 'profile':
    s3_profile = os.environ.get('DR_LOCAL_S3_PROFILE', 'default')
else: # mode is 'role'
    s3_profile = None
s3_yaml_name = os.environ.get('DR_LOCAL_S3_EVAL_PARAMS_FILE', 'eval-params.yaml')
yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))

session = boto3.session.Session(profile_name=s3_profile)
s3_client = session.client('s3', region_name=s3_region, endpoint_url=s3_endpoint_url)

yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))
local_yaml_path = os.path.abspath(os.path.join(os.environ.get('DR_DIR'),'tmp', 'eval-params-' + str(round(time.time())) + '.yaml'))

with open(local_yaml_path, 'w') as yaml_file:
    yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)

s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)
