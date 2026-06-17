#!/usr/bin/python3

#
# Enqueues a single racer profile onto the virtual racing SQS queue.
#
# The virtual_event worker consumes one message per race. Each profile points at
# the model to load (inputModel) and where to write results (output*). For the
# MVP this enqueues the locally trained model (DR_LOCAL_S3_MODEL_PREFIX) as a
# single TIME_TRIAL racer.
#

import argparse
import json
import os
import time
import uuid

import boto3


def env(name, default=None):
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def main():
    bucket = env('DR_LOCAL_S3_BUCKET', 'bucket')
    model_prefix = env('DR_LOCAL_S3_MODEL_PREFIX', 'rl-deepracer-sagemaker')

    parser = argparse.ArgumentParser(description="Add a racer to the virtual racing queue.")
    parser.add_argument('--alias', default=env('DR_VIRTUAL_RACER_ALIAS', 'racer1'),
                        help="Display alias for the racer.")
    parser.add_argument('--bucket', default=bucket,
                        help="S3 bucket holding the model and receiving outputs.")
    parser.add_argument('--model-prefix', default=env('DR_VIRTUAL_RACER_MODEL_PREFIX', model_prefix),
                        help="S3 key prefix of the model to race (inputModel).")
    parser.add_argument('--color', default=env('DR_CAR_COLOR', 'Red'),
                        help="Car color.")
    parser.add_argument('--body', default=env('DR_CAR_BODY_SHELL_TYPE', 'deepracer'),
                        help="Car body shell type.")
    args = parser.parse_args()

    output_root = '{}/virtual'.format(args.model_prefix.rstrip('/'))

    profile = {
        "racerAlias": args.alias,
        "carConfig": {
            "carColor": args.color,
            "bodyShellType": args.body,
        },
        "inputModel": {
            "s3BucketName": args.bucket,
            "s3KeyPrefix": args.model_prefix,
        },
        "outputStatus": {
            "s3BucketName": args.bucket,
            "s3KeyPrefix": '{}/status'.format(output_root),
        },
        "outputMetrics": {
            "s3BucketName": args.bucket,
            "s3KeyPrefix": '{}/metrics'.format(output_root),
        },
        "outputSimTrace": {
            "s3BucketName": args.bucket,
            "s3KeyPrefix": '{}/simtrace'.format(output_root),
        },
        "outputMp4": {
            "s3BucketName": args.bucket,
            "s3KeyPrefix": '{}/mp4'.format(output_root),
        },
    }

    region = env('DR_AWS_APP_REGION', 'us-east-1')
    endpoint_url = env('DR_VIRTUAL_SQS_HOST_ENDPOINT_URL', None)
    queue_name = env('DR_VIRTUAL_SQS_QUEUE_NAME', 'deepracer-virtual.fifo')

    s3_mode = env('DR_LOCAL_S3_AUTH_MODE', 'profile')
    s3_profile = env('DR_LOCAL_S3_PROFILE', 'default') if s3_mode == 'profile' else None

    session = boto3.session.Session(profile_name=s3_profile)
    sqs = session.client('sqs', region_name=region, endpoint_url=endpoint_url)

    queue_url = sqs.get_queue_url(QueueName=queue_name)['QueueUrl']

    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(profile),
        MessageGroupId='virtual',
        MessageDeduplicationId='{}-{}'.format(int(time.time()), uuid.uuid4().hex),
    )

    print("Enqueued racer '{}' (model s3://{}/{}) onto {}".format(
        args.alias, args.bucket, args.model_prefix, queue_name))


if __name__ == '__main__':
    main()
