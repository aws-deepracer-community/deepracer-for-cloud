#!/usr/bin/python3

import boto3
import sys
import os 
import time
import json
import io
import yaml

config = {}
config['AWS_REGION'] = os.environ.get('DR_AWS_APP_REGION', 'us-east-1')
config['JOB_TYPE'] = 'TRAINING'
config['KINESIS_VIDEO_STREAM_NAME'] = os.environ.get('DR_KINESIS_STREAM_NAME', 'my-kinesis-stream')
config['METRIC_NAME'] = 'TrainingRewardScore'
config['METRIC_NAMESPACE'] = 'AWSDeepRacer'
config['METRICS_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')

metrics_prefix = os.environ.get('DR_LOCAL_S3_METRICS_PREFIX', None)
if metrics_prefix is not None:
    config['METRICS_S3_OBJECT_KEY'] = '{}/TrainingMetrics.json'.format(metrics_prefix)
else:
    config['METRICS_S3_OBJECT_KEY'] = 'DeepRacer-Metrics/TrainingMetrics-{}.json'.format(str(round(time.time())))

config['MODEL_METADATA_FILE_S3_KEY'] = os.environ.get('DR_LOCAL_S3_MODEL_METADATA_KEY', 'custom_files/model_metadata.json') 
config['NUMBER_OF_EPISODES'] = os.environ.get('DR_NUMBER_OF_EPISODES', '0')
config['REWARD_FILE_S3_KEY'] = os.environ.get('DR_LOCAL_S3_REWARD_KEY', 'custom_files/reward_function.py')
config['ROBOMAKER_SIMULATION_JOB_ACCOUNT_ID'] = os.environ.get('', 'Dummy')
config['NUM_WORKERS'] = os.environ.get('DR_WORKERS', 1)
config['SAGEMAKER_SHARED_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
config['SAGEMAKER_SHARED_S3_PREFIX'] = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
config['SIMTRACE_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
config['SIMTRACE_S3_PREFIX'] = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
config['TARGET_REWARD_SCORE'] = os.environ.get('DR_TARGET_REWARD_SCORE', 'None')
config['TRAINING_JOB_ARN'] = 'arn:Dummy'

# Car and training 
config['CAR_COLOR'] = os.environ.get('DR_CAR_COLOR', 'Red')
config['CAR_NAME'] = os.environ.get('DR_CAR_NAME', 'MyCar')
config['RACE_TYPE'] = os.environ.get('DR_RACE_TYPE', 'TIME_TRIAL')
config['WORLD_NAME'] = os.environ.get('DR_WORLD_NAME', 'LGSWide')
config['NUMBER_OF_TRIALS'] = os.environ.get('DR_EVAL_NUMBER_OF_TRIALS', '5')
config['DISPLAY_NAME'] = os.environ.get('DR_DISPLAY_NAME', 'racer1')
config['RACER_NAME'] = os.environ.get('DR_RACER_NAME', 'racer1')

config['ALTERNATE_DRIVING_DIRECTION'] = os.environ.get('DR_ALTERNATE_DRIVING_DIRECTION', 'false')
config['CHANGE_START_POSITION'] = os.environ.get('DR_CHANGE_START_POSITION', 'true')
config['ENABLE_DOMAIN_RANDOMIZATION'] = os.environ.get('DR_ENABLE_DOMAIN_RANDOMIZATION', 'false')

# Object Avoidance
if config['RACE_TYPE'] == 'OBJECT_AVOIDANCE':
    config['NUMBER_OF_OBSTACLES'] = os.environ.get('DR_OA_NUMBER_OF_OBSTACLES', '6')
    config['MIN_DISTANCE_BETWEEN_OBSTACLES'] = os.environ.get('DR_OA_MIN_DISTANCE_BETWEEN_OBSTACLES', '2.0')
    config['RANDOMIZE_OBSTACLE_LOCATIONS'] = os.environ.get('DR_OA_RANDOMIZE_OBSTACLE_LOCATIONS', 'True')
    config['PSEUDO_RANDOMIZE_OBSTACLE_LOCATIONS'] = os.environ.get('DR_OA_PSEUDO_RANDOMIZE_OBSTACLE_LOCATIONS', 'False')
    config['NUMBER_OF_PSEUDO_RANDOM_PLACEMENTS'] = os.environ.get('DR_OA_NUMBER_OF_PSEUDO_RANDOM_PLACEMENTS', '2')
    config['IS_OBSTACLE_BOT_CAR'] = os.environ.get('DR_OA_IS_OBSTACLE_BOT_CAR', 'false')

# Head to Bot
if config['RACE_TYPE'] == 'HEAD_TO_BOT':
    config['IS_LANE_CHANGE'] = os.environ.get('DR_H2B_IS_LANE_CHANGE', 'False')
    config['LOWER_LANE_CHANGE_TIME'] = os.environ.get('DR_H2B_LOWER_LANE_CHANGE_TIME', '3.0')
    config['UPPER_LANE_CHANGE_TIME'] = os.environ.get('DR_H2B_UPPER_LANE_CHANGE_TIME', '5.0')
    config['LANE_CHANGE_DISTANCE'] = os.environ.get('DR_H2B_LANE_CHANGE_DISTANCE', '1.0')
    config['NUMBER_OF_BOT_CARS'] = os.environ.get('DR_H2B_NUMBER_OF_BOT_CARS', '0')
    config['MIN_DISTANCE_BETWEEN_BOT_CARS'] = os.environ.get('DR_H2B_MIN_DISTANCE_BETWEEN_BOT_CARS', '2.0')
    config['RANDOMIZE_BOT_CAR_LOCATIONS'] = os.environ.get('DR_H2B_RANDOMIZE_BOT_CAR_LOCATIONS', 'False')
    config['BOT_CAR_SPEED'] = os.environ.get('DR_H2B_BOT_CAR_SPEED', '0.2')

s3_endpoint_url = os.environ.get('DR_LOCAL_S3_ENDPOINT_URL', None)
s3_region = config['AWS_REGION']
s3_bucket = config['SAGEMAKER_SHARED_S3_BUCKET']
s3_prefix = config['SAGEMAKER_SHARED_S3_PREFIX']
s3_mode = os.environ.get('DR_LOCAL_S3_AUTH_MODE','profile')
if s3_mode == 'profile':
    s3_profile = os.environ.get('DR_LOCAL_S3_PROFILE', 'default')
else: # mode is 'role'
    s3_profile = None
s3_yaml_name = os.environ.get('DR_LOCAL_S3_TRAINING_PARAMS_FILE', 'training_params.yaml')
yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))

session = boto3.session.Session(profile_name=s3_profile)
s3_client = session.client('s3', region_name=s3_region, endpoint_url=s3_endpoint_url)

yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name))
local_yaml_path = os.path.abspath(os.path.join(os.environ.get('DR_DIR'),'tmp', 'training-params-' + str(round(time.time())) + '.yaml'))

with open(local_yaml_path, 'w') as yaml_file:
    yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)

s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)
