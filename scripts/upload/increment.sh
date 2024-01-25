#!/bin/bash

usage() {
    echo "Usage: $0 [-f] [-w] [-p <model-prefix>] [-d <delimiter>]"
    echo ""
    echo "Command will increment a numerical suffix on the current upload model."
    echo "-p model  Sets the to-be name to be <model-prefix> rather than auto-incremeneting the previous model."
    echo "-d delim  Delimiter in model-name (e.g. '-' in 'test-model-1')"
    echo "-f        Force. Ask for no confirmations."
    echo "-w        Wipe the S3 prefix to ensure that two models are not mixed."
    exit 1
}

trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

OPT_DELIM='-'

while getopts ":fwp:d:" opt; do
    case $opt in

    f)
        OPT_FORCE="True"
        ;;
    p)
        OPT_PREFIX="$OPTARG"
        ;;
    w)
        OPT_WIPE="--delete"
        ;;
    d)
        OPT_DELIM="$OPTARG"
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

CONFIG_FILE=$DR_CONFIG
echo "Configuration file $CONFIG_FILE will be updated."

## Read in data
CURRENT_UPLOAD_MODEL=$(grep -e "^DR_UPLOAD_S3_PREFIX" ${CONFIG_FILE} | awk '{split($0,a,"="); print a[2] }')
CURRENT_UPLOAD_MODEL_NUM=$(echo "${CURRENT_UPLOAD_MODEL}" |
    awk -v DELIM="${OPT_DELIM}" '{ n=split($0,a,DELIM); if (a[n] ~ /[0-9]*/) print a[n]; else print ""; }')
if [[ -z ${CURRENT_UPLOAD_MODEL_NUM} ]]; then
    NEW_UPLOAD_MODEL="${CURRENT_UPLOAD_MODEL}${OPT_DELIM}1"
else
    NEW_UPLOAD_MODEL_NUM=$(echo "${CURRENT_UPLOAD_MODEL_NUM} + 1" | bc)
    NEW_UPLOAD_MODEL=$(echo $CURRENT_UPLOAD_MODEL | sed "s/${CURRENT_UPLOAD_MODEL_NUM}\$/${NEW_UPLOAD_MODEL_NUM}/")
fi

if [[ -n "${NEW_UPLOAD_MODEL}" ]]; then
    echo "Incrementing model from ${CURRENT_UPLOAD_MODEL} to ${NEW_UPLOAD_MODEL}"
    if [[ -z "${OPT_FORCE}" ]]; then
        read -r -p "Are you sure? [y/N] " response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo "Aborting."
            exit 1
        fi
    fi
    sed -i.bak -re "s/(DR_UPLOAD_S3_PREFIX=).*$/\1$NEW_UPLOAD_MODEL/g" "$CONFIG_FILE" && echo "Done."
else
    echo "Error in determining new model. Aborting."
    exit 1
fi

export DR_UPLOAD_S3_PREFIX=$(eval echo "${NEW_UPLOAD_MODEL}")

if [[ -n "${OPT_WIPE}" ]]; then
    MODEL_DIR_S3=$(aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 ls s3://${DR_LOCAL_S3_BUCKET}/${NEW_UPLOAD_MODEL})
    if [[ -n "${MODEL_DIR_S3}" ]]; then
        echo "The new model's S3 prefix s3://${DR_LOCAL_S3_BUCKET}/${NEW_UPLOAD_MODEL} exists. Will wipe."
    fi
    if [[ -z "${OPT_FORCE}" ]]; then
        read -r -p "Are you sure? [y/N] " response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo "Aborting."
            exit 1
        fi
    fi
    aws ${DR_LOCAL_PROFILE_ENDPOINT_URL} s3 rm s3://${DR_LOCAL_S3_BUCKET}/${NEW_UPLOAD_MODEL} --recursive
fi
