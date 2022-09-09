#!/bin/bash

usage(){
        echo "Usage: $0 [-f] [-n] [-w] [-d] [-c] [-b] [-t] [-h]"
  echo "       -f        Force upload. No confirmation question."
  echo "       -n        Name of profile"
  echo "       -w        Wipes the target profile location before saving."
  echo "       -d        Dry-Run mode. Does not perform any write or delete operations on target."
  echo "       -c        Include latest checkpoint"
  echo "       -b        Include best checkpoint"
  echo "       -t        Just used for testing"
  echo "       -h        Usage"
  exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}


while getopts "n:wdfcbth" opt; do
case $opt in
n) OPT_PROFILENAME=${OPTARG}
;;
w) OPT_WIPE="--delete"
;;
d) OPT_DRYRUN="--dryrun"
;;
f) OPT_FORCE="-f"
;;
c) OPT_LASTCHECKPOINT="-c"
;;
b) OPT_BESTCHECKPOINT="-b"
;;
t) OPT_TESTING="test"
;;
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done


if [[ -z "${OPT_PROFILENAME}" ]];
then
  echo "No profile name defined. Exiting."
  exit 1
fi


if [[ -n "${OPT_DRYRUN}" ]];
then
  echo "*** DRYRUN MODE ***"
fi


if [[ -n "${OPT_TESTING}" ]];
then
  echo "*** TEST MODE ***"
  #only code inside this block will run, then program will exit

  echo "testing completed"
  exit
fi

export TARGET_PROFILE_S3_BUCKET=${DR_UPLOAD_S3_BUCKET}
export TARGET_PROFILE_S3_PREFIX=drfc_profiles/${OPT_PROFILENAME}
export WORK_DIR=${DR_DIR}/

# Confirm uploads
if [[ -z "${OPT_FORCE}" ]];
then
    echo "Ready to save profile ${OPT_PROFILENAME} to s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/"
    read -r -p "Are you sure? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "Aborting."
        exit 1
    fi
fi


# Upload configuration information
TARGET_RUN_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/run.env"
TARGET_SYSTEM_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/system.env"
TARGET_CUSTOMFILES_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/custom_files/reward_function.py"
TARGET_CUSTOMFILES_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/custom_files"

aws s3 sync ${WORK_DIR}/custom_files ${TARGET_CUSTOMFILES_S3_KEY} ${OPT_DRYRUN}
aws s3 cp ${WORK_DIR}/run.env ${TARGET_RUN_S3_KEY} ${OPT_DRYRUN}
aws s3 cp ${WORK_DIR}/system.env ${TARGET_SYSTEM_S3_KEY} ${OPT_DRYRUN}


#determine number of workers and upload
num_workers=$(while read LINE; do grep "DR_WORKERS"; done < ${DR_DIR}/system.env | cut -d "=" -f2)
if [[ $num_workers -gt 1 ]]; then
    for (( num=2; num<=$num_workers; num++))
    do
        aws s3 cp ${WORK_DIR}/worker-${num}.env s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/worker-${num}.env ${OPT_DRYRUN}
    done
fi


## LOAD CHECKPOINT FILES

if [ -z ${OPT_BESTCHECKPOINT} ] && [ -z ${OPT_LASTCHECKPOINT} ]; then
    echo "Don't Save Checkpoints"
else

    ## save most recent checkpoint information (borrow from upload-model?)
    SOURCE_S3_BUCKET=${DR_LOCAL_S3_BUCKET}
    SOURCE_S3_MODEL_PREFIX=${DR_LOCAL_S3_MODEL_PREFIX}

    export WORK_DIR=${DR_DIR}/tmp/upload/
    mkdir -p ${WORK_DIR} && rm -rf ${WORK_DIR} && mkdir -p ${WORK_DIR}model ${WORK_DIR}ip

    # Upload information on model.
    TARGET_PARAMS_FILE_S3_KEY="s3://${TARGET_S3_BUCKET}/${TARGET_S3_PREFIX}/training_params.yaml"

    # Download checkpoint file
    echo "Looking for model to upload from s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/"
    CHECKPOINT_INDEX=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 cp s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model/deepracer_checkpoints.json ${WORK_DIR}model/ --no-progress | awk '{print $4}' | xargs readlink -f 2> /dev/null)


    if [ -z "$CHECKPOINT_INDEX" ]; then
      echo "No checkpoint file available at s3://${SOURCE_S3_BUCKET}/${SOURCE_S3_MODEL_PREFIX}/model. Exiting."
      exit 1
    fi


    if [ "$OPT_LASTCHECKPOINT" ]; then
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
        echo ${CHECKPOINT_FILE} | tee ${WORK_DIR}model/.coach_checkpoint > /dev/null
    else
        echo "Checkpoint not found. Exiting."
        exit 1
    fi

    # Confirm uploads
    if [[ -z "${OPT_FORCE}" ]];
    then
        echo "Ready to save checkpoint?"
        read -r -p "Are you sure? [y/N] " response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo "Aborting."
            exit 1
        fi
    fi

    TARGET_MODELFILES_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/model"

    cd ${WORK_DIR}
    echo ${CHECKPOINT_JSON} > ${WORK_DIR}model/deepracer_checkpoints.json
    aws ${DR_UPLOAD_PROFILE} s3 sync ${WORK_DIR}model/ ${TARGET_MODELFILES_S3_KEY} ${OPT_DRYRUN}

fi
