#!/usr/bin/env bash

# Library for CPU functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# CPU Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

function detect_gpu() {
  # Function to detect if a GPU is available

    emit_cmd docker build -t local/gputest - < "$INSTALL_DIR"/utils/Dockerfile.gpu-detect
    local GPUS
    GPUS=$(docker run --rm --gpus all local/gputest 2> /dev/null | awk  '/Device: ./' | wc -l )
    if [ $? -ne 0 ] || [ "$GPUS" -eq 0 ]
    then
        false
    else
        true
    fi
}
