#!/usr/bin/env python3
"""
This script checks for model files in an S3 bucket, downloads, and renames them based on a specified pattern.

Environment Variables:
- DR_LOCAL_S3_BUCKET: Name of the S3 bucket.
- DR_LOCAL_S3_PROFILE: AWS profile name for boto3 session.
- DR_REMOTE_MINIO_URL: (Optional) MinIO server URL.

Usage:
    python download-car-model.py --pattern <prefix_pattern>
"""

import boto3
import os
import fnmatch
import argparse

# Load environment variables
bucket_name = os.getenv('DR_LOCAL_S3_BUCKET')
profile_name = os.getenv('DR_LOCAL_S3_PROFILE')
minio_url = os.getenv('DR_REMOTE_MINIO_URL')

# Set up boto3 session with the specified profile
session = boto3.Session(profile_name=profile_name)
endpoint_url = minio_url if minio_url else None
s3 = session.client('s3', endpoint_url=endpoint_url)

def check_model_file(prefix):
    """
    Check if a model.tar.gz file exists in the specified prefix.

    Args:
        prefix (str): The prefix to check within the S3 bucket.

    Returns:
        bool: True if the model file is found, False otherwise.
    """
    try:
        response = s3.list_objects_v2(Bucket=bucket_name, Prefix=f"{prefix}output/")
        for obj in response.get('Contents', []):
            if obj['Key'].endswith('model.tar.gz'):
                print(f"Found model.tar.gz in {prefix}output/")
                return f"{obj['Key']}"

        response = s3.list_objects_v2(Bucket=bucket_name, Prefix=prefix)
        for obj in response.get('Contents', []):
            if obj['Key'].endswith('carfile.tar.gz'):
                print(f"Found carfile.tar.gz in {prefix}")
                return f"{obj['Key']}"

        print(f"No model.tar.gz found in {prefix}output/ and no carfile.tar.gz found in {prefix}")
        return None
    except Exception as e:
        print(f"Error checking {prefix}: {e}")
        return None

def get_matching_prefixes(prefix_pattern):
    """
    Get a list of prefixes in the S3 bucket that match the given pattern.

    Args:
        prefix_pattern (str): The pattern to match prefixes against.

    Returns:
        list: A list of matching prefixes.
    """
    try:
        response = s3.list_objects_v2(Bucket=bucket_name, Delimiter='/')
        prefixes = [prefix['Prefix'] for prefix in response.get('CommonPrefixes', [])]
        matching_prefixes = fnmatch.filter(prefixes, prefix_pattern)
        return matching_prefixes
    except Exception as e:
        print(f"Error listing prefixes: {e}")
        return []

def download_and_rename_model_file(prefix, file_key):
    """
    Download and rename the model.tar.gz file from the specified file key.

    Args:
        prefix (str): The prefix of the model file.
        file_key (str): The S3 key of the model file to download.

    Returns:
        bool: True if the model file is downloaded and renamed, False otherwise.
    """
    try:
        local_filename = os.path.join("tmp", f"{prefix.rstrip('/')}.tar.gz")
        s3.download_file(bucket_name, file_key, local_filename)
        print(f"Downloaded and renamed {file_key} to {local_filename}")
        return True
    except Exception as e:
        print(f"Error downloading {file_key}: {e}")
        return False

def validate_s3_connection():
    """
    Validate the S3 connection using the provided bucket name and profile name.

    Raises:
        ValueError: If bucket name or profile name is not defined.
        ConnectionError: If unable to connect to the S3 bucket.
    """
    if not bucket_name or not profile_name:
        raise ValueError("Bucket name and profile name must be defined in environment variables.")
    
    try:
        s3.head_bucket(Bucket=bucket_name)
        print(f"Successfully connected to bucket: {bucket_name}")
    except Exception as e:
        raise ConnectionError(f"Unable to connect to the bucket: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Check and download model files from S3.')
    parser.add_argument('--pattern', type=str, required=True, help='Pattern for prefixes to check')
    args = parser.parse_args()

    validate_s3_connection()

    matching_prefixes = get_matching_prefixes(args.pattern)
    for prefix in matching_prefixes:
        model_file_path = check_model_file(prefix)
        if model_file_path:
            download_and_rename_model_file(prefix, model_file_path)