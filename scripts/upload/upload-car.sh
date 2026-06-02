#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [-b] [-f] [-L] [-p <model-prefix>]"
  echo "       -b              Use best checkpoint. Default is last checkpoint."
  echo "       -f              Force. Do not ask for confirmation."
  echo "       -L              Upload to local S3 bucket."
  echo "       -p <prefix>     Model prefix. Default: DR_LOCAL_S3_MODEL_PREFIX."
  exit 1
}

trap ctrl_c INT

function ctrl_c() {
  echo "Requested to stop."
  exit 1
}

while getopts ":bfLp:h" opt; do
  case $opt in
  b)
    OPT_CHECKPOINT="-b"
    ;;
  f)
    OPT_FORCE="force"
    ;;
  L)
    OPT_LOCAL="Local"
    ;;
  p)
    OPT_PREFIX="$OPTARG"
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

# Determine model prefix
if [[ -n "${OPT_PREFIX}" ]]; then
  MODEL_PREFIX="${OPT_PREFIX}"
else
  MODEL_PREFIX="${DR_LOCAL_S3_MODEL_PREFIX}"
fi

# Create the car tar.gz via create-car-zip.sh
CREATE_ARGS="${OPT_CHECKPOINT}"
if [[ -n "${OPT_PREFIX}" ]]; then
  CREATE_ARGS="${CREATE_ARGS} -p ${OPT_PREFIX}"
fi

CAR_ZIP_FILE="${DR_DIR}/${MODEL_PREFIX}.tar.gz"
CREATE_ARGS="${CREATE_ARGS} -o ${CAR_ZIP_FILE}"

${DR_DIR}/scripts/upload/create-car-zip.sh ${CREATE_ARGS}
if [ $? -ne 0 ]; then
  echo "Failed to create car zip. Exiting." >&2
  exit 1
fi

# Determine upload target
if [[ -z "${OPT_LOCAL}" ]]; then
  TARGET_S3_BUCKET="${DR_UPLOAD_S3_BUCKET}"
  UPLOAD_PROFILE="${DR_UPLOAD_PROFILE}"
  TARGET_S3_PREFIX="${DR_UPLOAD_S3_PREFIX}"
else
  TARGET_S3_BUCKET="${DR_LOCAL_S3_BUCKET}"
  UPLOAD_PROFILE="${DR_LOCAL_PROFILE_ENDPOINT_URL}"
  TARGET_S3_PREFIX="${MODEL_PREFIX}"
fi

if [[ -z "${OPT_FORCE}" ]]; then
  echo "Ready to upload ${MODEL_PREFIX}.tar.gz to s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/${MODEL_PREFIX}.tar.gz"
  read -r -p "Are you sure? [y/N] " response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Aborting."
    exit 1
  fi
fi

aws ${UPLOAD_PROFILE} s3 cp "${CAR_ZIP_FILE}" \
  "s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/${MODEL_PREFIX}.tar.gz"
