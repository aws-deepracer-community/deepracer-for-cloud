#!/usr/bin/env bash

usage() {
    echo "Usage: $0 [-L] [-f]"
    echo "       -f        Force. Do not ask for confirmation."
    echo "       -L        Upload model to the local S3 bucket."
    exit 1
}

trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

while getopts ":Lf" opt; do
    case $opt in
    L)
        OPT_LOCAL="Local"
        ;;
    f)
        OPT_FORCE="force"
        ;;
    h)
        usage
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        usage
        ;;
    esac
done

# This script creates the tar.gz file necessary to operate inside a deepracer physical car
# The file is created directly from within the sagemaker container, using the most recent checkpoint

# Find sagemaker container for the current run (respects DR_RUN_ID and DR_LOCAL_S3_MODEL_PREFIX)
SAGEMAKER_CONTAINER=$(dr-find-sagemaker)
if [[ -z "${SAGEMAKER_CONTAINER}" ]]; then
    echo "No Sagemaker container found for run ${DR_RUN_ID}. Exiting."
    exit 1
fi
echo "Found Sagemaker container: ${SAGEMAKER_CONTAINER}"

#create tmp directory if it doesnt already exist
rm -rf "${DR_DIR}/tmp/car_upload" && mkdir -p "${DR_DIR}/tmp/car_upload"
cd "${DR_DIR}/tmp/car_upload" || exit 1
#The files we want are located inside the sagemaker container at /opt/ml/model.  Copy them to the tmp directory
docker cp "${SAGEMAKER_CONTAINER}:/opt/ml/model" "${DR_DIR}/tmp/car_upload"
cd "${DR_DIR}/tmp/car_upload/model" || exit 1
#create a tar.gz file containing all of these files
tar -czvf carfile.tar.gz *

# Upload files
if [[ -z "${OPT_FORCE}" ]]; then
    if [[ -n "${OPT_LOCAL}" ]]; then
        echo "Ready to upload car model to local s3://${DR_LOCAL_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}."
    else
        echo "Ready to upload car model to remote s3://${DR_UPLOAD_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}."
    fi
    read -r -p "Are you sure? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

#upload to s3
if [[ -n "${OPT_LOCAL}" ]]; then
    aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp carfile.tar.gz s3://${DR_LOCAL_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}/carfile.tar.gz
else
    aws ${DR_UPLOAD_PROFILE} s3 cp carfile.tar.gz s3://${DR_UPLOAD_S3_BUCKET}/${DR_UPLOAD_S3_PREFIX}/carfile.tar.gz
fi
