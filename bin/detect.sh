#!/usr/bin/env bash

## What am I?
if [[ -f /var/run/cloud-init/instance-data.json ]]; then
    # We have a cloud-init environment (Azure or AWS).
    CLOUD_NAME=$(jq -r '.v1."cloud-name"' /var/run/cloud-init/instance-data.json)
    if [[ "${CLOUD_NAME}" == "azure" ]]; then
        export CLOUD_NAME
        export CLOUD_INSTANCETYPE=$(jq -r '.ds."meta_data".imds.compute."vmSize"' /var/run/cloud-init/instance-data.json)
    elif [[ "${CLOUD_NAME}" == "aws" ]]; then
        export CLOUD_NAME
        export CLOUD_INSTANCETYPE=$(jq -r '.ds."meta-data"."instance-type"' /var/run/cloud-init/instance-data.json)
    else
        export CLOUD_NAME=local
    fi
else
    export CLOUD_NAME=local
fi
