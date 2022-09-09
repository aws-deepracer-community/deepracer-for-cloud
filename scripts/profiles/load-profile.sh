#!/bin/bash

usage(){
        echo "Usage: $0 [-f] [-l] [-n] [-d] [-t] [-h] "
  echo "       -f        Force upload. No confirmation question."
  echo "       -l        List available profiles"
  echo "       -n        Name of profile"
  echo "       -d        Dry-Run mode. Does not perform any write or delete operations on target."
  echo "       -t        Test mode"
  echo "       -h        Usage"
        exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}


while getopts "ln:dfth" opt; do
case $opt in
l) OPT_LISTPROFILES="list"
;;
n) OPT_PROFILENAME=${OPTARG}
;;
d) OPT_DRYRUN="--dryrun"
;;
f) OPT_FORCE="-f"
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

export TARGET_PROFILE_S3_PREFIX=drfc_profiles/${OPT_PROFILENAME}
export TARGET_PROFILE_S3_BUCKET=${DR_UPLOAD_S3_BUCKET}

export WORK_DIR=${DR_DIR}/

if [ ! -z "$OPT_LISTPROFILES" ];
then
    aws s3 ls s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}
    exit
fi

if [[ -n "${OPT_DRYRUN}" ]];
then
  echo "*** DRYRUN MODE ***"
fi

if [[ -z "${OPT_PROFILENAME}" ]];
then
  echo "No profile name defined.  Use -n <profilename>  Exiting."
  exit 1
fi

if [[ -n "${OPT_TESTING}" ]];
then
  echo "*** TEST MODE ***"
  #only code inside this block will run, then program will exit
  exit
fi



# load configuration information.
TARGET_RUN_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/run.env"
TARGET_SYSTEM_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/system.env"
TARGET_CUSTOMFILES_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/custom_files/reward_function.py"
TARGET_CUSTOMFILES_S3_KEY="s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/custom_files"




aws s3 sync ${TARGET_CUSTOMFILES_S3_KEY} ${WORK_DIR}/custom_files ${OPT_DRYRUN}
aws s3 cp ${TARGET_RUN_S3_KEY} ${WORK_DIR}/run.env ${OPT_DRYRUN}
aws s3 cp ${TARGET_SYSTEM_S3_KEY} ${WORK_DIR}/system.env ${OPT_DRYRUN}

#determine number of workers and upload
if [ -e $WORK_DIR/worker-2.env ]
then rm $WORK_DIR/worker-*
fi
num_workers=$(while read LINE; do grep "DR_WORKERS"; done < ${DR_DIR}/system.env | cut -d "=" -f2)
if [[ $num_workers -gt 1 ]]; then
    for (( num=2; num<=$num_workers; num++))
    do
        aws s3 cp s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/worker-${num}.env ${WORK_DIR}/worker-${num}.env ${OPT_DRYRUN}
    done
fi


# Confirm uploads
if [[ -z "${OPT_FORCE}" ]];
then
    echo "Do you wish to load saved checkpoints?  Warning -- will overwrite"
    read -r -p "Are you sure? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "Aborting."
        exit 1
    fi
fi

nameprefix=$(while read LINE; do grep "DR_LOCAL_S3_MODEL_PREFIX="; done <${DR_DIR}/run.env | cut -d "=" -f2)

DATA_DIR=${DR_DIR}/data/minio/bucket/${nameprefix}
mkdir -p ${DATA_DIR} && rm -rf ${DATA_DIR} && mkdir -p ${DATA_DIR}/model && mkdir -p ${DATA_DIR}/ip
aws s3 sync s3://${TARGET_PROFILE_S3_BUCKET}/${TARGET_PROFILE_S3_PREFIX}/model/ ${DATA_DIR}/model/ ${OPT_DRYRUN}


MODEL_METADATA_S3_KEY="${TARGET_CUSTOMFILES_S3_KEY}/model_metadata.json"
aws s3 cp ${MODEL_METADATA_S3_KEY} ${DATA_DIR}/model/model_metadata.json ${OPT_DRYRUN}
REWARD_S3_KEY="${TARGET_CUSTOMFILES_S3_KEY}/reward_function.py"
aws s3 cp ${REWARD_S3_KEY} ${DATA_DIR}/reward_function.py ${OPT_DRYRUN}
HYPERPARAMS_S3_KEY="${TARGET_CUSTOMFILES_S3_KEY}/hyperparameters.json"
aws s3 cp ${HYPERPARAMS_S3_KEY} ${DATA_DIR}/ip/hyperparameters.json ${OPT_DRYRUN}

echo "You must increment training to leverage this checkpoint"
