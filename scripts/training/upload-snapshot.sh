#!/bin/bash

S3_BUCKET=${UPLOAD_S3_BUCKET}
S3_PREFIX=${UPLOAD_S3_PREFIX}

WORK_DIR=/mnt/deepracer
MODEL_DIR=${WORK_DIR}/rl-deepracer-sagemaker/model/
MODEL_REWARD=$(pwd)/../../custom_files/reward.py
MODEL_HYPER=$(pwd)/../../custom_files/hyperparameters.json
MODEL_NAME=$UPLOAD_MODEL_NAME

display_usage() { 
    echo -e "\nUsage:\n./upload-snapshot.sh -c checkpoint \n"
}

# check whether user had supplied -h or --help . If yes display usage 
if [[ ( $# == "--help") ||  $# == "-h" ]]; then 
display_usage
exit 0
fi 

while getopts ":c:" opt; do
case $opt in
c) CHECKPOINT="$OPTARG"
;;
\?) echo "Invalid option -$OPTARG" >&2
;;
esac
done

# echo 'checkpoint recieved: ' ${CHECKPOINT}

if [ -z "$CHECKPOINT" ]; then
  echo "Checkpoint not supplied, checking for latest checkpoint"
  CHECKPOINT_FILE=$MODEL_DIR"checkpoint"

  if [ ! -f ${CHECKPOINT_FILE} ]; then
    echo "Checkpoint file not found!"
    return 1
  else
    echo "found checkpoint index file "$CHECKPOINT_FILE
  fi;

  FIRST_LINE=$(head -n 1 $CHECKPOINT_FILE)
  CHECKPOINT=`echo $FIRST_LINE | sed "s/[model_checkpoint_path: [^ ]*//"`
  CHECKPOINT=`echo $CHECKPOINT | sed 's/[_][^ ]*//'`
  CHECKPOINT=`echo $CHECKPOINT | sed 's/"//g'`
  echo "latest checkpoint = "$CHECKPOINT
else
  echo "Checkpoint supplied: ["${CHECKPOINT}"]"
fi

mkdir -p $WORK_DIR/tmp_upload && rm -rf $WORK_DIR/tmp_upload/*

MODEL_FILE=$MODEL_DIR"model_"$CHECKPOINT".pb"
METADATA_FILE=$MODEL_DIR"model_metadata.json"


if test ! -f "$MODEL_FILE"; then
    echo "$MODEL_FILE doesn't exist"
    return 1
else
  cp $MODEL_FILE $WORK_DIR/tmp_upload/  
fi

if test ! -f "$METADATA_FILE"; then
    echo "$METADATA_FILE doesn't exist"
    return 1
else
  cp $METADATA_FILE $WORK_DIR/tmp_upload/  
fi


for i in $( find $MODEL_DIR -type f -name $CHECKPOINT"*" ); do
    cp $i $WORK_DIR/tmp_upload/  
done

ls ${MODEL_DIR}${CHECKPOINT}_Step-*.ckpt.index | xargs -n 1 basename | sed 's/[.][^ ]*//'

CONTENT=$(ls ${MODEL_DIR}${CHECKPOINT}_Step-*.ckpt.index | xargs -n 1 basename | sed 's/[.][^ ]*//')
echo ${CONTENT}

echo 'model_checkpoint_path: "'${CONTENT}'.ckpt"' > $WORK_DIR/tmp_upload/checkpoint

# # upload files to s3
for filename in $WORK_DIR/tmp_upload/*; do
    aws s3 cp $filename s3://$S3_BUCKET/$S3_PREFIX/model/
done
aws s3 cp $MODEL_HYPER s3://$S3_BUCKET/$S3_PREFIX/ip/
# tar -czvf $WORK_DIR/$MODEL_NAME-${CHECKPOINT}-checkpoint.tar.gz $WORK_DIR/checkpoint/*

# # upload meta-data
aws s3 cp $METADATA_FILE s3://$S3_BUCKET/model-metadata/$MODEL_NAME/
aws s3 cp $MODEL_REWARD s3://$S3_BUCKET/reward-functions/$MODEL_NAME/reward_function.py

echo 'done uploading model!'









