#!/usr/bin/env python
# coding: utf-8


import sagemaker
import boto3
import sys
import os
import glob
import re
import subprocess
from IPython.display import Markdown
from time import gmtime, strftime
sys.path.append("common")
from misc import get_execution_role, wait_for_s3_object
from sagemaker.rl import RLEstimator, RLToolkit, RLFramework
from markdown_helper import *



# S3 bucket
boto_session = boto3.session.Session(
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "minio"), 
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "miniokey"),
    region_name=os.environ.get("AWS_REGION", "us-east-1"))
s3Client = boto_session.resource("s3", use_ssl=False,
endpoint_url=os.environ.get("S3_ENDPOINT_URL", "http://127.0.0.1:9000"))

sage_session = sagemaker.local.LocalSession(boto_session=boto_session, s3_client=s3Client)
s3_bucket = os.environ.get("MODEL_S3_BUCKET", "bucket") #sage_session.default_bucket() 
s3_output_path = 's3://{}/'.format(s3_bucket) # SDK appends the job name and output folder

# ### Define Variables

# We define variables such as the job prefix for the training jobs and s3_prefix for storing metadata required for synchronization between the training and simulation jobs


job_name_prefix = 'rl-deepracer' # this should be MODEL_S3_PREFIX, but that already ends with "-sagemaker"

# create unique job name
tm = gmtime()
job_name = s3_prefix = job_name_prefix + "-sagemaker"#-" + strftime("%y%m%d-%H%M%S", tm) #Ensure S3 prefix contains SageMaker
s3_prefix_robomaker = job_name_prefix + "-robomaker"#-" + strftime("%y%m%d-%H%M%S", tm) #Ensure that the S3 prefix contains the keyword 'robomaker'


# Duration of job in seconds (5 hours)
job_duration_in_seconds = 24 * 60 * 60

aws_region = sage_session.boto_region_name

if aws_region not in ["us-west-2", "us-east-1", "eu-west-1"]:
    raise Exception("This notebook uses RoboMaker which is available only in US East (N. Virginia), US West (Oregon) and EU (Ireland). Please switch to one of these regions.")
print("Model checkpoints and other metadata will be stored at: {}{}".format(s3_output_path, job_name))


s3_location = "s3://%s/%s" % (s3_bucket, s3_prefix)
print("Uploading to " + s3_location)


metric_definitions = [
    # Training> Name=main_level/agent, Worker=0, Episode=19, Total reward=-102.88, Steps=19019, Training iteration=1
    {'Name': 'reward-training',
     'Regex': '^Training>.*Total reward=(.*?),'},
    
    # Policy training> Surrogate loss=-0.32664725184440613, KL divergence=7.255815035023261e-06, Entropy=2.83156156539917, training epoch=0, learning_rate=0.00025
    {'Name': 'ppo-surrogate-loss',
     'Regex': '^Policy training>.*Surrogate loss=(.*?),'},
     {'Name': 'ppo-entropy',
     'Regex': '^Policy training>.*Entropy=(.*?),'},
   
    # Testing> Name=main_level/agent, Worker=0, Episode=19, Total reward=1359.12, Steps=20015, Training iteration=2
    {'Name': 'reward-testing',
     'Regex': '^Testing>.*Total reward=(.*?),'},
]


# We use the RLEstimator for training RL jobs.
# 
# 1. Specify the source directory which has the environment file, preset and training code.
# 2. Specify the entry point as the training code
# 3. Specify the choice of RL toolkit and framework. This automatically resolves to the ECR path for the RL Container.
# 4. Define the training parameters such as the instance count, instance type, job name, s3_bucket and s3_prefix for storing model checkpoints and metadata. **Only 1 training instance is supported for now.**
# 4. Set the RLCOACH_PRESET as "deepracer" for this example.
# 5. Define the metrics definitions that you are interested in capturing in your logs. These can also be visualized in CloudWatch and SageMaker Notebooks.

# In[ ]:


RLCOACH_PRESET = "deepracer"

gpu_available = os.environ.get("GPU_AVAILABLE", False)
# 'local' for cpu, 'local_gpu' for nvidia gpu (and then you don't have to set default runtime to nvidia)
instance_type = "local_gpu" if gpu_available else "local"
image_name = "crr0004/sagemaker-rl-tensorflow:{}".format(
    "nvidia" if gpu_available else "console")

estimator = RLEstimator(entry_point="training_worker.py",
                        source_dir='src',
                        dependencies=["common/sagemaker_rl"],
                        toolkit=RLToolkit.COACH,
                        toolkit_version='0.11',
                        framework=RLFramework.TENSORFLOW,
                        sagemaker_session=sage_session,
                        #bypass sagemaker SDK validation of the role
                        role="aaa/",
                        train_instance_type=instance_type,
                        train_instance_count=1,
                        output_path=s3_output_path,
                        base_job_name=job_name_prefix,
                        image_name=image_name,
                        train_max_run=job_duration_in_seconds, # Maximum runtime in seconds
                        hyperparameters={"s3_bucket": s3_bucket,
                                         "s3_prefix": s3_prefix,
                                         "aws_region": aws_region,
                                         "model_metadata_s3_key": "s3://{}/custom_files/model_metadata.json".format(s3_bucket),
                                         "RLCOACH_PRESET": RLCOACH_PRESET,
                                         "batch_size": 64,
                                         "num_epochs": 10,
                                         "stack_size" : 1,
                                         "lr" : 0.00035,
                                         "exploration_type" : "categorical",
                                         "e_greedy_value" : 0.05,
                                         "epsilon_steps" : 10000,
                                         "beta_entropy" : 0.01,
                                         "discount_factor" : 0.999,
                                         "loss_type": "mean squared error",
                                         "num_episodes_between_training" : 20,
                                         "term_cond_max_episodes" : 100000,
                                         "term_cond_avg_score" : 100000
                                         #"pretrained_s3_bucket": "{}".format(s3_bucket),
                                         #"pretrained_s3_prefix": "rl-deepracer-pretrained"
                                         # "loss_type": "mean squared error",
                                      },
                        metric_definitions = metric_definitions,
                        s3_client=s3Client
                        #subnets=default_subnets, # Required for VPC mode
                        #security_group_ids=default_security_groups, # Required for VPC mode
                    )

estimator.fit(job_name=job_name, wait=False)
