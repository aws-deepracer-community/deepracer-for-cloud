#!/bin/bash

while getopts ":c:" opt; do
case $opt in
c) OPT_CHECKPOINT="$OPTARG"
;;
\?) echo "Invalid option -$OPTARG" >&2
;;
esac
done

TARGET_S3_BUCKET=${UPLOAD_S3_BUCKET}
TARGET_S3_PREFIX=${UPLOAD_S3_PREFIX}

SOURCE_S3_BUCKET=${LOCAL_S3_BUCKET}
SOURCE_S3_MODEL_PREFIX=${LOCAL_S3_MODEL_PREFIX}
SOURCE_S3_CONFIG=${LOCAL_S3_CUSTOM_FILES_PREFIX}

WORK_DIR=/mnt/deepracer/tmp/
mkdir -p ${WORK_DIR} && rm -rf ${WORK_DIR} && mkdir -p ${WORK_DIR}model

# Download information on model.
PARAM_FILE=$(aws s3 sync s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX} ${WORK_DIR} --exclude "*" --include "training_params*" --no-progress | awk '{print $4}' | xargs readlink -f)
if [ -n "$PARAM_FILE" ];
then
  TARGET_METADATA_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/"$(awk '/MODEL_METADATA_FILE_S3_KEY/ {print $2}' $PARAM_FILE | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
  TARGET_REWARD_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/"$(awk '/REWARD_FILE_S3_KEY/ {print $2}' $PARAM_FILE | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
  TARGET_METRICS_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/"$(awk '/METRICS_S3_OBJECT_KEY/ {print $2}' $PARAM_FILE | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
  TARGET_HYPERPARAM_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/ip/hyperparameters.json"
  MODEL_NAME=$(awk '/MODEL_METADATA_FILE_S3_KEY/ {print $2}' $PARAM_FILE | awk '{split($0,a,"/"); print a[2] }')
  echo "Preparing upload for model ${MODEL_NAME}."
else
  echo "No DeepRacer information found in s3://${UPLOAD_S3_BUCKET}/${UPLOAD_S3_PREFIX}. Exiting"
  exit 1
fi


# Check if metadata-files are available
REWARD_FILE=$(aws $LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_CONFIG}/reward.py ${WORK_DIR} --no-progress | awk '/reward.py$/ {print $4}'| xargs readlink -f)
METADATA_FILE=$(aws $LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_CONFIG}/model_metadata.json ${WORK_DIR} --no-progress | awk '/model_metadata.json$/ {print $4}'| xargs readlink -f)
HYPERPARAM_FILE=$(aws $LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_CONFIG}/hyperparameters.json ${WORK_DIR} --no-progress | awk '/hyperparameters.json$/ {print $4}'| xargs readlink -f)
METRICS_FILE=$(aws $LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/metrics/metric.json ${WORK_DIR} --no-progress | awk '/metric.json$/ {print $4}'| xargs readlink -f)

if [ -n "$METADATA_FILE" ] && [ -n "$REWARD_FILE" ] && [ -n "$METRICS_FILE" ] && [ -n "$HYPERPARAM_FILE" ]; 
then
    echo "All meta-data files found. Looking for checkpoint."
    # SOURCE_METADATA_FILE_S3_KEY="s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_CONFIG}/reward.py"
    # SOURCE_REWARD_FILE="s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_CONFIG}/model_metadata.json"
    # SOURCE_METRICS_FILE="s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_CONFIG}/metrics/metric.json"
fi

# Download checkpoint file
CHECKPOINT_FILE=$(aws ${LOCAL_PROFILE_ENDPOINT_URL} s3 sync s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/ ${WORK_DIR}model --exclude "*" --include "checkpoint" --no-progress | awk '{print $4}' | xargs readlink -f)

if [ -z "$CHECKPOINT_FILE" ]; then
  echo "No checkpoint file available at s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model. Exiting."
  exit 1
fi

if [ -z "$OPT_CHECKPOINT" ]; then
  echo "Checkpoint not supplied, checking for latest checkpoint"

  FIRST_LINE=$(head -n 1 $CHECKPOINT_FILE)
  CHECKPOINT_PREFIX=$(echo $FIRST_LINE | sed "s/[model_checkpoint_path: [^ ]*//" | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
  CHECKPOINT=`echo $CHECKPOINT_PREFIX | sed 's/[_][^ ]*//'`
  echo "Latest checkpoint = "$CHECKPOINT
else
  CHECKPOINT="${OPT_CHECKPOINT}" 
  CHECKPOINT_PREFIX=$(cat $CHECKPOINT_FILE | grep "all_model_checkpoint_paths: \"$CHECKPOINT" | sed "s/[all_model_checkpoint_paths: [^ ]*//"  | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
  echo "Checkpoint supplied: ["${CHECKPOINT}"]"
fi

# Find checkpoint & model files - download
if [ -n "$CHECKPOINT_PREFIX" ]; then
    CHECKPOINT_MODEL_FILES=$(aws ${LOCAL_PROFILE_ENDPOINT_URL} s3 sync s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/ ${WORK_DIR}model/ --exclude "*" --include "${CHECKPOINT_PREFIX}*" --include "model_${CHECKPOINT}.pb" --no-progress | awk '{print $4}' | xargs readlink -f)
    cp ${METADATA_FILE} ${WORK_DIR}model/
    echo "model_checkpoint_path: \"${CHECKPOINT_PREFIX}\"" | tee ${CHECKPOINT_FILE}
else
    echo "Checkpoint not found. Exiting."
    exit 1
fi

# Upload files
echo "Uploading files for model ${MODEL_NAME} to s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/"
aws s3 sync ${WORK_DIR}model/ s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/model/ 
aws s3 cp ${REWARD_FILE} ${TARGET_REWARD_FILE_S3_KEY} 
aws s3 cp ${METADATA_FILE} ${TARGET_METADATA_FILE_S3_KEY} 
aws s3 cp ${METRICS_FILE} ${TARGET_METRICS_FILE_S3_KEY} 
aws s3 cp ${HYPERPARAM_FILE} ${TARGET_HYPERPARAM_FILE_S3_KEY}
