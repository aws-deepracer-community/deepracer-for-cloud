#!/usr/bin/python3

from datetime import datetime
import boto3
import sys
import os 
import time
import json
import io
import yaml

train_time = datetime.now().strftime('%Y%m%d%H%M%S')

config = {}
config['AWS_REGION'] = os.environ.get('DR_AWS_APP_REGION', 'us-east-1')
config['JOB_TYPE'] = 'TRAINING'
config['KINESIS_VIDEO_STREAM_NAME'] = os.environ.get('DR_KINESIS_STREAM_NAME', '')
config['METRICS_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')

metrics_prefix = os.environ.get('DR_LOCAL_S3_METRICS_PREFIX', None)
if metrics_prefix is not None:
    config['METRICS_S3_OBJECT_KEY'] = '{}/TrainingMetrics.json'.format(metrics_prefix)
else:
    config['METRICS_S3_OBJECT_KEY'] = 'DeepRacer-Metrics/TrainingMetrics-{}.json'.format(train_time)

config['MODEL_METADATA_FILE_S3_KEY'] = os.environ.get('DR_LOCAL_S3_MODEL_METADATA_KEY', 'custom_files/model_metadata.json') 
config['REWARD_FILE_S3_KEY'] = os.environ.get('DR_LOCAL_S3_REWARD_KEY', 'custom_files/reward_function.py')
config['ROBOMAKER_SIMULATION_JOB_ACCOUNT_ID'] = os.environ.get('', 'Dummy')
config['NUM_WORKERS'] = os.environ.get('DR_WORKERS', 1)
config['SAGEMAKER_SHARED_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
config['SAGEMAKER_SHARED_S3_PREFIX'] = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
config['SIMTRACE_S3_BUCKET'] = os.environ.get('DR_LOCAL_S3_BUCKET', 'bucket')
config['SIMTRACE_S3_PREFIX'] = os.environ.get('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')
config['TRAINING_JOB_ARN'] = 'arn:Dummy'

# Car and training 
config['BODY_SHELL_TYPE'] = os.environ.get('DR_CAR_BODY_SHELL_TYPE', 'deepracer')
config['CAR_COLOR'] = os.environ.get('DR_CAR_COLOR', 'Red')
config['CAR_NAME'] = os.environ.get('DR_CAR_NAME', 'MyCar')
config['RACE_TYPE'] = os.environ.get('DR_RACE_TYPE', 'TIME_TRIAL')
config['WORLD_NAME'] = os.environ.get('DR_WORLD_NAME', 'LGSWide')
config['DISPLAY_NAME'] = os.environ.get('DR_DISPLAY_NAME', 'racer1')
config['RACER_NAME'] = os.environ.get('DR_RACER_NAME', 'racer1')

config['REVERSE_DIR'] = os.environ.get('DR_TRAIN_REVERSE_DIRECTION', False)
config['ALTERNATE_DRIVING_DIRECTION'] = os.environ.get('DR_TRAIN_ALTERNATE_DRIVING_DIRECTION', os.environ.get('DR_ALTERNATE_DRIVING_DIRECTION', 'false'))
config['CHANGE_START_POSITION'] = os.environ.get('DR_TRAIN_CHANGE_START_POSITION', os.environ.get('DR_CHANGE_START_POSITION', 'true'))
config['ROUND_ROBIN_ADVANCE_DIST'] = os.environ.get('DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST', '0.05')
config['START_POSITION_OFFSET'] = os.environ.get('DR_TRAIN_START_POSITION_OFFSET', '0.00')
config['ENABLE_DOMAIN_RANDOMIZATION'] = os.environ.get('DR_ENABLE_DOMAIN_RANDOMIZATION', 'false')
config['MIN_EVAL_TRIALS'] = os.environ.get('DR_TRAIN_MIN_EVAL_TRIALS', '5')
config['CAMERA_MAIN_ENABLE'] = os.environ.get('DR_CAMERA_MAIN_ENABLE', 'True')
config['CAMERA_SUB_ENABLE'] = os.environ.get('DR_CAMERA_SUB_ENABLE', 'True')
config['BEST_MODEL_METRIC'] = os.environ.get('DR_TRAIN_BEST_MODEL_METRIC', 'progress')

# Object Avoidance
if config['RACE_TYPE'] == 'OBJECT_AVOIDANCE':
    config['NUMBER_OF_OBSTACLES'] = os.environ.get('DR_OA_NUMBER_OF_OBSTACLES', '6')
    config['MIN_DISTANCE_BETWEEN_OBSTACLES'] = os.environ.get('DR_OA_MIN_DISTANCE_BETWEEN_OBSTACLES', '2.0')
    config['RANDOMIZE_OBSTACLE_LOCATIONS'] = os.environ.get('DR_OA_RANDOMIZE_OBSTACLE_LOCATIONS', 'True')
    config['IS_OBSTACLE_BOT_CAR'] = os.environ.get('DR_OA_IS_OBSTACLE_BOT_CAR', 'false')
    config['OBSTACLE_TYPE'] = os.environ.get('DR_OA_OBSTACLE_TYPE', 'box_obstacle')

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
    config['PENALTY_SECONDS'] = os.environ.get('DR_H2B_BOT_CAR_PENALTY', '2.0')

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
local_yaml_path = os.path.abspath(os.path.join(os.environ.get('DR_DIR'),'tmp', 'training-params-' + train_time + '.yaml'))

with open(local_yaml_path, 'w') as yaml_file:
    yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)

# Copy the reward function to the s3 prefix bucket for compatability with DeepRacer console.
reward_function_key = os.path.normpath(os.path.join(s3_prefix, "reward_function.py"))
copy_source = {
    'Bucket': s3_bucket,
    'Key': config['REWARD_FILE_S3_KEY']
}
s3_client.copy(copy_source, Bucket=s3_bucket, Key=reward_function_key)

# Training with different configurations on each worker (aka Multi Config training)
config['MULTI_CONFIG'] = os.environ.get('DR_TRAIN_MULTI_CONFIG', 'False')
num_workers = int(config['NUM_WORKERS'])

if config['MULTI_CONFIG'] == "True" and num_workers > 1:
    
    multi_config = {}
    multi_config['multi_config'] = [None] * num_workers

    for i in range(1,num_workers+1,1):
        if i == 1:
            # copy training_params to training_params_1
            s3_yaml_name_list = s3_yaml_name.split('.')
            s3_yaml_name_temp = s3_yaml_name_list[0] + "_%d.yaml" % i

            #upload additional training params files
            yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name_temp))
            s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)            

            # Store in multi_config array
            multi_config['multi_config'][i - 1] = {'config_file': s3_yaml_name_temp,
                                                             'world_name': config['WORLD_NAME']}

        else:  # i >= 2 
            #read in additional configuration file.  format of file must be worker#-run.env
            location = os.path.abspath(os.path.join(os.environ.get('DR_DIR'),'worker-{}.env'.format(i)))
            with open(location, 'r') as fh:
                vars_dict = dict(
                    tuple(line.split('='))
                    for line in fh.read().splitlines() if not line.startswith('#')
                    )

            # Reset parameters for the configuration of this worker number
            os.environ.update(vars_dict)

            # Update car and training parameters
            config.update({'WORLD_NAME': os.environ.get('DR_WORLD_NAME')})
            config.update({'RACE_TYPE': os.environ.get('DR_RACE_TYPE')})
            config.update({'CAR_COLOR': os.environ.get('DR_CAR_COLOR')})
            config.update({'BODY_SHELL_TYPE': os.environ.get('DR_CAR_BODY_SHELL_TYPE')})
            config.update({'ALTERNATE_DRIVING_DIRECTION': os.environ.get('DR_TRAIN_ALTERNATE_DRIVING_DIRECTION')})
            config.update({'CHANGE_START_POSITION': os.environ.get('DR_TRAIN_CHANGE_START_POSITION')})
            config.update({'ROUND_ROBIN_ADVANCE_DIST': os.environ.get('DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST')})
            config.update({'ENABLE_DOMAIN_RANDOMIZATION': os.environ.get('DR_ENABLE_DOMAIN_RANDOMIZATION')})
            config.update({'START_POSITION_OFFSET': os.environ.get('DR_TRAIN_START_POSITION_OFFSET', '0.00')})
            config.update({'REVERSE_DIR': os.environ.get('DR_TRAIN_REVERSE_DIRECTION', False)})
            config.update({'CAMERA_MAIN_ENABLE': os.environ.get('DR_CAMERA_MAIN_ENABLE', 'True')})
            config.update({'CAMERA_SUB_ENABLE': os.environ.get('DR_CAMERA_SUB_ENABLE', 'True')})  
            
            # Update Object Avoidance parameters
            if config['RACE_TYPE'] == 'OBJECT_AVOIDANCE':
                config.update({'NUMBER_OF_OBSTACLES': os.environ.get('DR_OA_NUMBER_OF_OBSTACLES')})
                config.update({'MIN_DISTANCE_BETWEEN_OBSTACLES': os.environ.get('DR_OA_MIN_DISTANCE_BETWEEN_OBSTACLES')})
                config.update({'RANDOMIZE_OBSTACLE_LOCATIONS': os.environ.get('DR_OA_RANDOMIZE_OBSTACLE_LOCATIONS')})
                config.update({'IS_OBSTACLE_BOT_CAR': os.environ.get('DR_OA_IS_OBSTACLE_BOT_CAR')})
                config.update({'OBSTACLE_TYPE': os.environ.get('DR_OA_OBSTACLE_TYPE', 'box_obstacle')})

                object_position_str = os.environ.get('DR_OA_OBJECT_POSITIONS', "")
                if object_position_str != "":
                    object_positions = []
                    for o in object_position_str.replace('"','').split(";"):
                        object_positions.append(o)
                    config.update({'OBJECT_POSITIONS': object_positions})
                    config.update({'NUMBER_OF_OBSTACLES': str(len(object_positions))})
                else:
                    config.pop('OBJECT_POSITIONS',[])
            else:
                config.pop('NUMBER_OF_OBSTACLES', None)
                config.pop('MIN_DISTANCE_BETWEEN_OBSTACLES', None)
                config.pop('RANDOMIZE_OBSTACLE_LOCATIONS', None)
                config.pop('IS_OBSTACLE_BOT_CAR', None)
                config.pop('OBJECT_POSITIONS',[])

            # Update Head to Bot parameters
            if config['RACE_TYPE'] == 'HEAD_TO_BOT':
                config.update({'IS_LANE_CHANGE': os.environ.get('DR_H2B_IS_LANE_CHANGE')})
                config.update({'LOWER_LANE_CHANGE_TIME': os.environ.get('DR_H2B_LOWER_LANE_CHANGE_TIME')})
                config.update({'UPPER_LANE_CHANGE_TIME': os.environ.get('DR_H2B_UPPER_LANE_CHANGE_TIME')})
                config.update({'LANE_CHANGE_DISTANCE': os.environ.get('DR_H2B_LANE_CHANGE_DISTANCE')})
                config.update({'NUMBER_OF_BOT_CARS': os.environ.get('DR_H2B_NUMBER_OF_BOT_CARS')})
                config.update({'MIN_DISTANCE_BETWEEN_BOT_CARS': os.environ.get('DR_H2B_MIN_DISTANCE_BETWEEN_BOT_CARS')})
                config.update({'RANDOMIZE_BOT_CAR_LOCATIONS': os.environ.get('DR_H2B_RANDOMIZE_BOT_CAR_LOCATIONS')})
                config.update({'BOT_CAR_SPEED': os.environ.get('DR_H2B_BOT_CAR_SPEED')})
                config.update({'PENALTY_SECONDS': os.environ.get('DR_H2B_BOT_CAR_PENALTY')})
            else:
                config.pop('IS_LANE_CHANGE', None)
                config.pop('LOWER_LANE_CHANGE_TIME', None)
                config.pop('UPPER_LANE_CHANGE_TIME', None)
                config.pop('LANE_CHANGE_DISTANCE', None)
                config.pop('NUMBER_OF_BOT_CARS', None)
                config.pop('MIN_DISTANCE_BETWEEN_BOT_CARS', None)
                config.pop('RANDOMIZE_BOT_CAR_LOCATIONS', None)
                config.pop('BOT_CAR_SPEED', None)

            #split string s3_yaml_name, insert the worker number, and add back on the .yaml extension
            s3_yaml_name_list = s3_yaml_name.split('.')
            s3_yaml_name_temp = s3_yaml_name_list[0] + "_%d.yaml" % i

            #upload additional training params files
            yaml_key = os.path.normpath(os.path.join(s3_prefix, s3_yaml_name_temp))
            local_yaml_path = os.path.abspath(os.path.join(os.environ.get('DR_DIR'),'tmp', 'training-params-' + train_time + '-' + str(i) + '.yaml'))
            with open(local_yaml_path, 'w') as yaml_file:
                yaml.dump(config, yaml_file, default_flow_style=False, default_style='\'', explicit_start=True)
            s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)

            # Store in multi_config array
            multi_config['multi_config'][i - 1] = {'config_file': s3_yaml_name_temp,
                                                             'world_name': config['WORLD_NAME']}

    print(json.dumps(multi_config))

else:
    s3_client.upload_file(Bucket=s3_bucket, Key=yaml_key, Filename=local_yaml_path)
