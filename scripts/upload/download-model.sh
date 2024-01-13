#!/bin/bash

usage() {
  echo "Usage: $0 [-f] [-w] [-d] -s <source-prefix> -t <target-prefix>"
  echo "       -f                Force download. No confirmation question."
  echo "       -w                Wipes the target AWS DeepRacer model structure before upload."
  echo "       -d                Dry-Run mode. Does not perform any write or delete operatios on target."
  echo "       -c                Copy config files into custom_files."
  echo "       -s source-url     Downloads model from specified S3 URL (s3://bucket/prefix)."
  echo "       -t target-prefix  Downloads model into specified prefix in local storage."
  exit 1
}

trap ctrl_c INT

function ctrl_c() {
  echo "Requested to stop."
  exit 1
}

while getopts "s:t:fwcdh" opt; do
  case $opt in
  f)
    OPT_FORCE="True"
    ;;
  c)
    OPT_CONFIG="Config"
    ;;
  d)
    OPT_DRYRUN="--dryrun"
    ;;
  w)
    OPT_WIPE="--delete"
    ;;
  t)
    OPT_TARGET="$OPTARG"
    ;;
  s)
    OPT_SOURCE="$OPTARG"
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

if [[ -n "${OPT_DRYRUN}" ]]; then
  echo "*** DRYRUN MODE ***"
fi

SOURCE_S3_URL="${OPT_SOURCE}"

if [[ -z "${SOURCE_S3_URL}" ]]; then
  echo "No source URL to download model from."
  exit 1
fi

TARGET_S3_BUCKET=${DR_LOCAL_S3_BUCKET}
TARGET_S3_PREFIX=${OPT_TARGET}
if [[ -z "${TARGET_S3_PREFIX}" ]]; then
  echo "No target prefix defined. Exiting."
  exit 1
fi

SOURCE_REWARD_FILE_S3_KEY="${SOURCE_S3_URL}/reward_function.py"
SOURCE_HYPERPARAM_FILE_S3_KEY="${SOURCE_S3_URL}/ip/hyperparameters.json"
SOURCE_METADATA_S3_KEY="${SOURCE_S3_URL}/model/model_metadata.json"

WORK_DIR=${DR_DIR}/tmp/download
mkdir -p ${WORK_DIR} && rm -rf ${WORK_DIR} && mkdir -p ${WORK_DIR}/config ${WORK_DIR}/full

# Check if metadata-files are available
REWARD_FILE=$(aws ${DR_UPLOAD_PROFILE} s3 cp "${SOURCE_REWARD_FILE_S3_KEY}" ${WORK_DIR}/config/ --no-progress | awk '/reward/ {print $4}' | xargs readlink -f 2>/dev/null)
METADATA_FILE=$(aws ${DR_UPLOAD_PROFILE} s3 cp "${SOURCE_METADATA_S3_KEY}" ${WORK_DIR}/config/ --no-progress | awk '/model_metadata.json$/ {print $4}' | xargs readlink -f 2>/dev/null)
HYPERPARAM_FILE=$(aws ${DR_UPLOAD_PROFILE} s3 cp "${SOURCE_HYPERPARAM_FILE_S3_KEY}" ${WORK_DIR}/config/ --no-progress | awk '/hyperparameters.json$/ {print $4}' | xargs readlink -f 2>/dev/null)

if [ -n "$METADATA_FILE" ] && [ -n "$REWARD_FILE" ] && [ -n "$HYPERPARAM_FILE" ]; then
  echo "All meta-data files found. Source model ${SOURCE_S3_URL} valid."
else
  echo "Meta-data files are not found. Source model ${SOURCE_S3_URL} not valid. Exiting."
  exit 1
fi

# Upload files
if [[ -z "${OPT_FORCE}" ]]; then
  echo "Ready to download model ${SOURCE_S3_URL} to local ${TARGET_S3_PREFIX}"
  read -r -p "Are you sure? [y/N] " response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Aborting."
    exit 1
  fi
fi

cd ${WORK_DIR}
aws ${DR_UPLOAD_PROFILE} s3 sync "${SOURCE_S3_URL}" ${WORK_DIR}/full/ ${OPT_DRYRUN}
aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 sync ${WORK_DIR}/full/ s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/ ${OPT_DRYRUN} ${OPT_WIPE}

if [[ -n "${OPT_CONFIG}" ]]; then
  echo "Copy configuration to custom_files"
  cp ${WORK_DIR}/config/* ${DR_DIR}/custom_files/
fi

echo "Done."
