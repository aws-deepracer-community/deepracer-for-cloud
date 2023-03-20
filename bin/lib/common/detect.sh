#!/usr/bin/env bash

# Library for Detect functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# Detect Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

function check_cloud_init() {
  if [[ -f /var/run/cloud-init/instance-data.json ]];
  then
      # We have a cloud-init environment (Azure or AWS).
      CLOUD_NAME=$(jq -r '.v1."cloud-name"' /var/run/cloud-init/instance-data.json)
      if [[ "${CLOUD_NAME}" == "azure" ]];
      then
          var_export CLOUD_NAME
          var_export CLOUD_INSTANCETYPE=$(jq -r '.ds."meta_data".imds.compute."vmSize"' /var/run/cloud-init/instance-data.json)
          log_message debug "Detected Azure cloud environment. Setting CLOUD_NAME to '${CLOUD_NAME}' and CLOUD_INSTANCETYPE to '${CLOUD_INSTANCETYPE}'"
      elif [[ "${CLOUD_NAME}" == "aws" ]];
      then
          var_export CLOUD_NAME
          var_export CLOUD_INSTANCETYPE=$(jq -r '.ds."meta-data"."instance-type"' /var/run/cloud-init/instance-data.json)
          log_message debug "Detected AWS cloud environment. Setting CLOUD_NAME to '${CLOUD_NAME}' and CLOUD_INSTANCETYPE to '${CLOUD_INSTANCETYPE}'"
      else
          var_export CLOUD_NAME=local
          log_message debug "Detected unknown cloud environment. Defaulting CLOUD_NAME to 'local'"
      fi
  else
      var_export CLOUD_NAME=local
      log_message debug "Cloud-init environment not found. Defaulting CLOUD_NAME to 'local'"
  fi
}
