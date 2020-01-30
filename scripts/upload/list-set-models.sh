#!/bin/bash
#set -x

usage(){
	echo "Usage: $0 [-h] [-s <model-prefix>] [-c]"
    echo "       -s model  Configures environment to upload into selected model."
    echo "       -c        Use local cache of models."
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

while getopts ":chs:" opt; do
case $opt in
s) OPT_SET="$OPTARG"
;;
c) OPT_CACHE="cache"
;;
h) usage
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

TARGET_S3_BUCKET=${UPLOAD_S3_BUCKET}
WORK_DIR=/mnt/deepracer/tmp-list
mkdir -p ${WORK_DIR} 

if [[ -n "${OPT_CACHE}" ]]; 
then
    PARAM_FILES=$(ls -t "${WORK_DIR}" )
    echo   -e "Using local cache..."
else
    PARAM_FILES=$(aws s3 ls s3://${TARGET_S3_BUCKET} --recursive | awk '/training_params*/ {print $4}' )
    echo   -e "\nLooking for DeepRacer models in s3://${TARGET_S3_BUCKET}...\n"
fi


if [[ -z "${PARAM_FILES}" ]];
then
    echo "No models found in s3://{TARGET_S3_BUCKET}. Exiting."
    exit 1
fi

if [[ -z "${OPT_SET}" ]];
then 
    echo   "+---------------------------------------------------------------------------+"
    printf "| %-40s | %-30s |\n" "Model Name" "Creation Time"
    echo   "+---------------------------------------------------------------------------+"

    for PARAM_FILE in $PARAM_FILES; do
        if [[ -z "${OPT_CACHE}" ]]; then
            aws s3 cp s3://${TARGET_S3_BUCKET}/${PARAM_FILE} ${WORK_DIR}/ --quiet 
            PARAM_FILE_L=$(echo "$PARAM_FILE" | awk '{split($0,a,"/"); print a[2]}')
        else
            PARAM_FILE_L=$PARAM_FILE
        fi
        MODIFICATION_TIME=$(stat -c %Y ${WORK_DIR}/${PARAM_FILE_L})
        MODIFICATION_TIME_STR=$(echo "@${MODIFICATION_TIME}" | xargs date -d )
        MODEL_NAME=$(awk '/MODEL_METADATA_FILE_S3_KEY/ {print $2}' ${WORK_DIR}/${PARAM_FILE_L} | awk '{split($0,a,"/"); print a[2] }')
        printf "| %-40s | %-30s |\n" "$MODEL_NAME" "$MODIFICATION_TIME_STR"
    done

    echo   "+---------------------------------------------------------------------------+"
    echo -e "\nSet the model with dr-set-upload-model -s <model-name>.\n"
else
    echo   -e "Looking for DeepRacer model ${OPT_SET} in s3://${TARGET_S3_BUCKET}..."

    for PARAM_FILE in $PARAM_FILES; do
        if [[ -z "${OPT_CACHE}" ]]; then
            aws s3 cp s3://${TARGET_S3_BUCKET}/${PARAM_FILE} ${WORK_DIR}/ --quiet 
            PARAM_FILE_L=$(echo "$PARAM_FILE" | awk '{split($0,a,"/"); print a[2]}')
            MODEL_NAME=$(awk '/MODEL_METADATA_FILE_S3_KEY/ {print $2}' ${WORK_DIR}/${PARAM_FILE_L} | awk '{split($0,a,"/"); print a[2] }')
            if [ "${MODEL_NAME}" = "${OPT_SET}" ]; then
                MATCHED_PREFIX=$(echo "$PARAM_FILE" | awk '{split($0,a,"/"); print a[1]}')
                echo "Found in ${MODEL_NAME} in ${MATCHED_PREFIX}".
                break
            fi
        else
            PARAM_FILE_L=$PARAM_FILE
            MODEL_NAME=$(awk '/MODEL_METADATA_FILE_S3_KEY/ {print $2}' ${WORK_DIR}/${PARAM_FILE_L} | awk '{split($0,a,"/"); print a[2] }')
            if [ "${MODEL_NAME}" = "${OPT_SET}" ]; then
                MATCHED_PREFIX=$(awk '/SAGEMAKER_SHARED_S3_PREFIX/ {print $2}' ${WORK_DIR}/${PARAM_FILE_L} | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
                echo "Found in ${MODEL_NAME} in ${MATCHED_PREFIX}".
                break
            fi
        fi
    done

    CONFIG_FILE=$(echo $DR_DIR/current-run.env)
    echo "Configuration file $CONFIG_FILE will be updated."
    if [[ -n "${MODEL_NAME}" ]];
    then
        read -r -p "Are you sure? [y/N] " response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo "Aborting."
            exit 1
        else
            sed -i.bak -re "s/(UPLOAD_S3_PREFIX=).*$/\1$MATCHED_PREFIX/g; s/(UPLOAD_MODEL_NAME=).*$/\1$MODEL_NAME/g" "$CONFIG_FILE" && echo "Done."
        fi
    fi
fi