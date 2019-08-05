#!/usr/bin/env bash

S3_BUCKET=$1
S3_PREFIX=$2

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

MODEL_DIR=${SCRIPTPATH}/../../docker/volumes/minio/bucket/rl-deepracer-pretrained/model/

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

mkdir -p checkpoint
MODEL_FILE=$MODEL_DIR"model_"$CHECKPOINT".pb"
METADATA_FILE=$MODEL_DIR"model_metadata.json"


if test ! -f "$MODEL_FILE"; then
    echo "$MODEL_FILE doesn't exist"
    return 1
else
  cp $MODEL_FILE checkpoint/  
fi

if test ! -f "$METADATA_FILE"; then
    echo "$METADATA_FILE doesn't exist"
    return 1
else
  cp $METADATA_FILE checkpoint/  
fi


for i in $( find $MODEL_DIR -type f -name $CHECKPOINT"*" ); do
    cp $i checkpoint/  
done

ls ${MODEL_DIR}${CHECKPOINT}_Step-*.ckpt.index | xargs -n 1 basename | sed 's/[.][^ ]*//'

CONTENT=$(ls ${MODEL_DIR}${CHECKPOINT}_Step-*.ckpt.index | xargs -n 1 basename | sed 's/[.][^ ]*//')
echo ${CONTENT}

echo 'model_checkpoint_path: "'${CONTENT}'.ckpt"' > checkpoint/checkpoint

# # upload files to s3
for filename in checkpoint/*; do
    aws s3 cp $filename s3://$S3_BUCKET/$S3_PREFIX/model/
done

tar -czvf ${CHECKPOINT}-checkpoint.tar.gz checkpoint/*

rm -rf checkpoint
echo 'done uploading model!'









