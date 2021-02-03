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
config['METRICS_S3_BUCKET'] = os.environ.get('TARGET_S3_BUCKET', 'bucket')
config['METRICS_S3_OBJECT_KEY'] = "{}/TrainingMetrics.json".format(os.environ.get('TARGET_S3_PREFIX', 'bucket'))
config['MODEL_METADATA_FILE_S3_KEY'] = "{}/model/model_metadata.json".format(os.environ.get('TARGET_S3_PREFIX', 'bucket'))
config['REWARD_FILE_S3_KEY'] = "{}/reward_function.py".format(os.environ.get('TARGET_S3_PREFIX', 'bucket'))
config['SAGEMAKER_SHARED_S3_BUCKET'] = os.environ.get('TARGET_S3_BUCKET', 'bucket')
config['SAGEMAKER_SHARED_S3_PREFIX'] = os.environ.get('TARGET_S3_PREFIX', 'rl-deepracer-sagemaker')

# Car and training 
config['BODY_SHELL_TYPE'] = os.environ.get('DR_CAR_BODY_SHELL_TYPE', 'deepracer')
if config['BODY_SHELL_TYPE'] == 'deepracer':
    config['CAR_COLOR'] = os.environ.get('DR_CAR_COLOR', 'Red')
config['CAR_NAME'] = os.environ.get('DR_CAR_NAME', 'MyCar')
config['RACE_TYPE'] = os.environ.get('DR_RACE_TYPE', 'TIME_TRIAL')
config['WORLD_NAME'] = os.environ.get('DR_WORLD_NAME', 'LGSWide')
config['DISPLAY_NAME'] = os.environ.get('DR_DISPLAY_NAME', 'racer1')
config['RACER_NAME'] = os.environ.get('DR_RACER_NAME', 'racer1')

config['ALTERNATE_DRIVING_DIRECTION'] = os.environ.get('DR_TRAIN_ALTERNATE_DRIVING_DIRECTION', os.environ.get('DR_ALTERNATE_DRIVING_DIRECTION', 'false'))
config['CHANGE_START_POSITION'] = os.environ.get('DR_TRAIN_CHANGE_START_POSITION', os.environ.get('DR_CHANGE_START_POSITION', 'true'))
config['ROUND_ROBIN_ADVANCE_DIST'] = os.environ.get('DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST', '0.05')
config['START_POSITION_OFFSET'] = os.environ.get('DR_TRAIN_START_POSITION_OFFSET', '0.00')
config['ENABLE_DOMAIN_RANDOMIZATION'] = os.environ.get('DR_ENABLE_DOMAIN_RANDOMIZATION', 'false')
config['MIN_EVAL_TRIALS'] = os.environ.get('DR_TRAIN_MIN_EVAL_TRIALS', '5')

# Object Avoidance
if config['RACE_TYPE'] == 'OBJECT_AVOIDANCE':
    config['NUMBER_OF_OBSTACLES'] = os.environ.get('DR_OA_NUMBER_OF_OBSTACLES', '6')
    config['MIN_DISTANCE_BETWEEN_OBSTACLES'] = os.environ.get('DR_OA_MIN_DISTANCE_BETWEEN_OBSTACLES', '2.0')
    config['RANDOMIZE_OBSTACLE_LOCATIONS'] = os.environ.get('DR_OA_RANDOMIZE_OBSTACLE_LOCATIONS', 'True')
    config['IS_OBSTACLE_BOT_CAR'] = os.environ.get('DR_OA_IS_OBSTACLE_BOT_CAR', 'false')

    object_position_str = os.environ.get('DR_OA_OBJECT_POSITIONS', "")
    if object_position_str != "":
        object_positions = []
        for o in object_position_str.split(";"):
            object_positions.append(o)
        config['OBJECT_POSITIONS'] = object_positions
        config['NUMBER_OF_OBSTACLES'] = str(len(object_positions))

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

local_yaml_path = os.path.abspath(os.path.join(os.environ.get('WORK_DIR'),'training_params.yaml'))
print(local_yaml_path)
with open(local_yaml_path, 'w') as yaml_file:
    yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)