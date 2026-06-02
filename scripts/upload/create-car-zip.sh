#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [-b] [-p <model-prefix>] [-o <output-file>]"
  echo "       -b              Use best checkpoint. Default is last checkpoint."
  echo "       -p <prefix>     Model prefix. Default: DR_LOCAL_S3_MODEL_PREFIX."
  echo "       -o <output>     Output file path. Default: <DR_DIR>/<model-prefix>.tar.gz"
  exit 1
}

trap ctrl_c INT

function ctrl_c() {
  echo "Requested to stop."
  exit 1
}

while getopts ":bp:o:h" opt; do
  case $opt in
  b)
    OPT_CHECKPOINT="best"
    ;;
  p)
    OPT_PREFIX="$OPTARG"
    ;;
  o)
    OPT_OUTPUT="$OPTARG"
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
elif [[ -n "${DR_LOCAL_S3_MODEL_PREFIX}" ]]; then
  MODEL_PREFIX="${DR_LOCAL_S3_MODEL_PREFIX}"
else
  echo "No model prefix specified and DR_LOCAL_S3_MODEL_PREFIX is not set." >&2
  exit 1
fi

# Determine output file
if [[ -n "${OPT_OUTPUT}" ]]; then
  OUTPUT_FILE="${OPT_OUTPUT}"
else
  mkdir -p "${DR_DIR}/data/output"
  OUTPUT_FILE="${DR_DIR}/data/output/${MODEL_PREFIX}.tar.gz"
fi

SOURCE_S3_BUCKET="${DR_LOCAL_S3_BUCKET}"

cd "${DR_DIR}"
WORK_DIR="${DR_DIR}/tmp/car_zip/"
rm -rf "${WORK_DIR}" && mkdir -p "${WORK_DIR}model" "${WORK_DIR}agent"

# Download checkpoint index
echo "Fetching checkpoint info from s3://${SOURCE_S3_BUCKET}/${MODEL_PREFIX}/model/"
aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp \
  "s3://${SOURCE_S3_BUCKET}/${MODEL_PREFIX}/model/deepracer_checkpoints.json" \
  "${WORK_DIR}model/" --no-progress

if [ ! -f "${WORK_DIR}model/deepracer_checkpoints.json" ]; then
  echo "deepracer_checkpoints.json not found at s3://${SOURCE_S3_BUCKET}/${MODEL_PREFIX}/model/. Exiting." >&2
  exit 1
fi

CHECKPOINT_INDEX="${WORK_DIR}model/deepracer_checkpoints.json"

# Select checkpoint
if [[ "${OPT_CHECKPOINT}" == "best" ]]; then
  echo "Using best checkpoint"
  CHECKPOINT_FILE=$(jq -r .best_checkpoint.name < "${CHECKPOINT_INDEX}")
else
  echo "Using last checkpoint"
  CHECKPOINT_FILE=$(jq -r .last_checkpoint.name < "${CHECKPOINT_INDEX}")
fi

if [[ -z "${CHECKPOINT_FILE}" || "${CHECKPOINT_FILE}" == "null" ]]; then
  echo "Could not determine checkpoint from deepracer_checkpoints.json. Exiting." >&2
  exit 1
fi

CHECKPOINT=$(echo "${CHECKPOINT_FILE}" | cut -f1 -d_)
echo "Selected checkpoint: ${CHECKPOINT} (${CHECKPOINT_FILE})"

# Download model.pb and model_metadata.json
echo "Downloading model_${CHECKPOINT}.pb ..."
aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp \
  "s3://${SOURCE_S3_BUCKET}/${MODEL_PREFIX}/model/model_${CHECKPOINT}.pb" \
  "${WORK_DIR}agent/model.pb" --no-progress

echo "Downloading model_metadata.json ..."
aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp \
  "s3://${SOURCE_S3_BUCKET}/${MODEL_PREFIX}/model/model_metadata.json" \
  "${WORK_DIR}model_metadata.json" --no-progress

if [ ! -f "${WORK_DIR}agent/model.pb" ]; then
  echo "model_${CHECKPOINT}.pb not found in S3. Exiting." >&2
  exit 1
fi

if [ ! -f "${WORK_DIR}model_metadata.json" ]; then
  echo "model_metadata.json not found in S3. Exiting." >&2
  exit 1
fi

# Create tar.gz with the expected on-car structure:
#   agent/model.pb
#   model_metadata.json
echo "Creating ${OUTPUT_FILE} ..."
tar -czf "${OUTPUT_FILE}" \
  -C "${WORK_DIR}" \
  agent/model.pb model_metadata.json

echo "Car zip created: ${OUTPUT_FILE}"
