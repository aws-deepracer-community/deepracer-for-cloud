#!/bin/bash

usage(){
	echo "Usage: $0 [-f] [-w] [-d] [-b] [-c <checkpoint>] [-p <model-prefix>]"
  echo "       -f        Force upload. No confirmation question."
  echo "       -w        Wipes the target AWS DeepRacer model structure before upload."
  echo "       -d        Dry-Run mode. Does not perform any write or delete operatios on target."
  echo "       -b        Uploads best checkpoint. Default is last checkpoint."
  echo "       -p model  Uploads model in specified S3 prefix."
  echo "       -i        Import model with the upload name"
  echo "       -I name   Import model with a specific name"
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

while getopts ":fwdhbp:c:" opt; do
case $opt in
b) OPT_CHECKPOINT="Best"
;; 
c) OPT_CHECKPOINT_NUM="$OPTARG"
;;
f) OPT_FORCE="True"
;;
d) OPT_DRYRUN="--dryrun"
;;
p) OPT_PREFIX="$OPTARG"
;;
w) OPT_WIPE="--delete"
;;
i) OPT_IMPORT="$DR_UPLOAD_S3_PREFIX"
;;
I) OPT_IMPORT="$OPTARG"
;;
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

if [[ -n "${OPT_DRYRUN}" ]];
then
  echo "*** DRYRUN MODE ***"
fi

export TARGET_S3_BUCKET=${DR_UPLOAD_S3_BUCKET}
export TARGET_S3_PREFIX=${DR_UPLOAD_S3_PREFIX}

if [[ -z "${DR_UPLOAD_S3_BUCKET}" ]];
then
  echo "No upload bucket defined. Exiting."
  exit 1
fi

if [[ -z "${DR_UPLOAD_S3_PREFIX}" ]];
then
  echo "No upload prefix defined. Exiting."
  exit 1
fi

SOURCE_S3_BUCKET=${DR_LOCAL_S3_BUCKET}
if [[ -n "${OPT_PREFIX}" ]];
then
  SOURCE_S3_MODEL_PREFIX=${OPT_PREFIX}
else
  SOURCE_S3_MODEL_PREFIX=${DR_LOCAL_S3_MODEL_PREFIX}
fi
SOURCE_S3_CONFIG=${DR_LOCAL_S3_CUSTOM_FILES_PREFIX}
SOURCE_S3_REWARD=${DR_LOCAL_S3_REWARD_KEY}
SOURCE_S3_METRICS="${DR_LOCAL_S3_METRICS_PREFIX}/TrainingMetrics.json"

export WORK_DIR=${DR_DIR}/tmp/upload/
mkdir -p ${WORK_DIR} && rm -rf ${WORK_DIR} && mkdir -p ${WORK_DIR}model ${WORK_DIR}ip

# Upload information on model.
TARGET_PARAMS_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/training_params.yaml"
TARGET_REWARD_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/reward_function.py"
TARGET_HYPERPARAM_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/ip/hyperparameters.json"
TARGET_METRICS_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/TrainingMetrics.json"

# Check if metadata-files are available
REWARD_IN_ROOT=$(aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 ls s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/reward_function.py 2> /dev/null | wc -l)
if [ "$REWARD_IN_ROOT" -ne 0 ];
then
    REWARD_FILE=$(aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/reward_function.py ${WORK_DIR} --no-progress | awk '/reward/ {print $4}'| xargs readlink -f 2> /dev/null)
else
    echo "Looking for Reward Function in s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_REWARD}"
    REWARD_FILE=$(aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_REWARD} ${WORK_DIR} --no-progress | awk '/reward/ {print $4}'| xargs readlink -f 2> /dev/null)
fi

METADATA_FILE=$(aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/model_metadata.json ${WORK_DIR} --no-progress | awk '/model_metadata.json$/ {print $4}'| xargs readlink -f 2> /dev/null)
HYPERPARAM_FILE=$(aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/ip/hyperparameters.json ${WORK_DIR} --no-progress | awk '/hyperparameters.json$/ {print $4}'| xargs readlink -f 2> /dev/null)
METRICS_FILE=$(aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_METRICS} ${WORK_DIR} --no-progress | awk '/metric/ {print $4}'| xargs readlink -f 2> /dev/null)

if [ -n "$METADATA_FILE" ] && [ -n "$REWARD_FILE" ] && [ -n "$HYPERPARAM_FILE" ] && [ -n "$METRICS_FILE" ]; 
then
    echo "All meta-data files found. Looking for checkpoint."
else
    echo "Meta-data files are not found. Exiting."
    exit 1
fi

# Download checkpoint file
echo "Looking for model to upload from s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/"
CHECKPOINT_INDEX=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/deepracer_checkpoints.json ${WORK_DIR}model/ --no-progress | awk '{print $4}' | xargs readlink -f 2> /dev/null) 

if [ -z "$CHECKPOINT_INDEX" ]; then
  echo "No checkpoint file available at s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model. Exiting."
  exit 1
fi

if [ -n "$OPT_CHECKPOINT_NUM" ]; then
  echo "Checking for checkpoint $OPT_CHECKPOINT_NUM"
  export OPT_CHECKPOINT_NUM
  CHECKPOINT_FILE=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 ls s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/ | perl -ne'print "$1\n" if /.*\s($ENV{OPT_CHECKPOINT_NUM}_Step-[0-9]{1,7}\.ckpt)\.index/')
  CHECKPOINT=`echo $CHECKPOINT_FILE | cut -f1 -d_`
  TIMESTAMP=`date +%s`
  CHECKPOINT_JSON_PART=$(jq -n '{ checkpoint: { name: $name, time_stamp: $timestamp | tonumber, avg_comp_pct: 50.0 } }' --arg name $CHECKPOINT_FILE --arg timestamp $TIMESTAMP)
  CHECKPOINT_JSON=$(echo $CHECKPOINT_JSON_PART | jq '. | {last_checkpoint: .checkpoint, best_checkpoint: .checkpoint}')
elif [ -z "$OPT_CHECKPOINT" ]; then
  echo "Checking for latest tested checkpoint"
  CHECKPOINT_FILE=`jq -r .last_checkpoint.name < $CHECKPOINT_INDEX`
  CHECKPOINT=`echo $CHECKPOINT_FILE | cut -f1 -d_`
  CHECKPOINT_JSON=$(jq '. | {last_checkpoint: .last_checkpoint, best_checkpoint: .last_checkpoint}' < $CHECKPOINT_INDEX )
  echo "Latest checkpoint = $CHECKPOINT"
else
  echo "Checking for best checkpoint"
  CHECKPOINT_FILE=`jq -r .best_checkpoint.name < $CHECKPOINT_INDEX`
  CHECKPOINT=`echo $CHECKPOINT_FILE | cut -f1 -d_`
  CHECKPOINT_JSON=$(jq '. | {last_checkpoint: .best_checkpoint, best_checkpoint: .best_checkpoint}' < $CHECKPOINT_INDEX )
  echo "Best checkpoint: $CHECKPOINT"
fi

# Find checkpoint & model files - download
if [ -n "$CHECKPOINT" ]; then
    CHECKPOINT_MODEL_FILES=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 sync s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/ ${WORK_DIR}model/ --exclude "*" --include "${CHECKPOINT}*" --include "model_${CHECKPOINT}.pb" --include "deepracer_checkpoints.json" --no-progress | awk '{print $4}' | xargs readlink -f 2> /dev/null)
    CHECKPOINT_MODEL_FILE_COUNT=$(echo $CHECKPOINT_MODEL_FILES | wc -l)
    if [ "$CHECKPOINT_MODEL_FILE_COUNT" -eq 0 ]; then
      echo "No model files found. Files possibly deleted. Try again."
      exit 1 
    fi
    cp ${METADATA_FILE} ${WORK_DIR}model/
#    echo "model_checkpoint_path: \"${CHECKPOINT_FILE}\"" | tee ${WORK_DIR}model/checkpoint
    echo ${CHECKPOINT_FILE} | tee ${WORK_DIR}model/.coach_checkpoint > /dev/null
else
    echo "Checkpoint not found. Exiting."
    exit 1
fi

# Create Training Params Yaml.
PARAMS_FILE=$(python3 $DR_DIR/scripts/upload/prepare-config.py)

# Upload files
if [[ -z "${OPT_FORCE}" ]];
then
    echo "Ready to upload model ${SOURCE_S3_MODEL_PREFIX} to s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/"
    read -r -p "Are you sure? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "Aborting."
        exit 1
    fi
fi

# echo "" > ${WORK_DIR}model/.ready 
cd ${WORK_DIR}
echo ${CHECKPOINT_JSON} > ${WORK_DIR}model/deepracer_checkpoints.json
aws ${DR_UPLOAD_PROFILE} s3 sync ${WORK_DIR}model/ s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/model/ ${OPT_DRYRUN} ${OPT_WIPE}
aws ${DR_UPLOAD_PROFILE} s3 cp ${REWARD_FILE} ${TARGET_REWARD_FILE_S3_KEY} ${OPT_DRYRUN}
aws ${DR_UPLOAD_PROFILE} s3 cp ${METRICS_FILE} ${TARGET_METRICS_FILE_S3_KEY} ${OPT_DRYRUN}
aws ${DR_UPLOAD_PROFILE} s3 cp ${PARAMS_FILE} ${TARGET_PARAMS_FILE_S3_KEY} ${OPT_DRYRUN}
aws ${DR_UPLOAD_PROFILE} s3 cp ${HYPERPARAM_FILE} ${TARGET_HYPERPARAM_FILE_S3_KEY} ${OPT_DRYRUN}

# After upload trigger the import
if [[ -n "${OPT_IMPORT}" ]];
then
    $DR_DIR/scripts/upload/prepare-config.py ${DR_UPLOAD_PROFILE} ${DR_UPLOAD_S3_ROLE} ${TARGET_S3_BUCKET} ${TARGET_S3_PREFIX} ${OPT_IMPORT}
fi