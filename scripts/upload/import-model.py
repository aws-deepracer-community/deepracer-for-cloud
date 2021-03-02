#!/usr/bin/python3

import boto3
import sys
import os 
import time
import json
import io
import yaml
import pandas as pd
from botocore.loaders import UnknownServiceError

# Read in command 
aws_profile = sys.argv[1]
aws_s3_role = sys.argv[2]
aws_s3_bucket = sys.argv[3]
aws_s3_prefix = sys.argv[4]
dr_model_name = sys.argv[5]

session = boto3.session.Session(region_name='us-east-1', profile_name=aws_profile)

try:
    dr = session.client('deepracer')
except UnknownServiceError:
    print ("Boto3 service 'deepracer' is not installed. Cannot import model.")
    print ("Install with 'pip install deepracer-utils' and 'python -m deepracer install-cli --force'")
    exit(1)

# Load model to check if it already exists
a = dr.list_models(ModelType='REINFORCEMENT_LEARNING', MaxResults=25)
model_dict = a['Models']
while "NextToken" in a:
    a = dr.list_models(ModelType='REINFORCEMENT_LEARNING', MaxResults=25, NextToken=a["NextToken"])
    model_dict.extend(a['Models'])

models = pd.DataFrame.from_dict(model_dict)

if models[models['ModelName']==dr_model_name].size > 0:
    sys.exit('Model {} already exists.'.format(dr_model_name))

# Import from S3
print('Importing from s3://{}/{}'.format(aws_s3_bucket,aws_s3_prefix))
response = dr.import_model(Name=dr_model_name, ModelArtifactsS3Path='s3://{}/{}'.format(aws_s3_bucket,aws_s3_prefix), RoleArn=aws_s3_role, Type='REINFORCEMENT_LEARNING')

if response['ResponseMetadata']['HTTPStatusCode'] == 200:
    print('Model importing as {}'.format(response['ModelArn']))
else:
    sys.exit('Error occcured when uploading')