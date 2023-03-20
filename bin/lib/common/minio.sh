#!/usr/bin/env bash

# Library for MINIO functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# MINIO Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

function alert_minio_image {
  # Check if DR_MINIO_IMAGE is configured in system.env

  local minio_version="$1"

  if [ "${DR_CLOUD,,}" == "local" ] && [ -z "${DR_MINIO_IMAGE}" ]; then
    log_message warning "DR_MINIO_IMAGE is not configured in system.env."
    log_message warning "System will default to tag ${minio_version}"
    export DR_MINIO_IMAGE="RELEASE.2022-10-24T18-35-07Z"
  fi
}
