#!/usr/bin/env bash

# Library for Autorun functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# Autorun Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script
# logging needs to be imported first
# utilities needs to be imported second
# cli needs to be imported third

function run_custom_autorun_script() {
    if [[ -f "$INSTALL_DIR/autorun.s3url" ]]; then
        log_message info "autorun.s3url file found, running custom autorun script"

        # Read training location from autorun.s3url
        TRAINING_LOC=$(awk 'NR==1 {print; exit}' "$INSTALL_DIR/autorun.s3url")

        # Extract training bucket and prefix from training location
        TRAINING_BUCKET=${TRAINING_LOC%%/*}
        if [[ "$TRAINING_LOC" == *"/"* ]]; then
            TRAINING_PREFIX=${TRAINING_LOC#*/}
        else
            TRAINING_PREFIX=""
        fi

        # Check if custom autorun script exists in S3 training bucket
        if aws s3api head-object --bucket "$TRAINING_BUCKET" --key "$TRAINING_PREFIX/autorun.sh" >/dev/null 2>&1; then
            log_message info "custom script exists, copying it to $INSTALL_DIR/bin/autorun.sh"
            aws s3 cp "s3://$TRAINING_LOC/autorun.sh" "$INSTALL_DIR/bin/autorun.sh"
        else
            log_message info "custom file does not exist, using local copy"
        fi

        # Make autorun.sh executable and run it
        chmod +x "$INSTALL_DIR"/bin/autorun.sh
        bash -c "source $INSTALL_DIR/bin/autorun.sh"
    else
        log_message info "autorun.s3url file not found, skipping custom autorun script"
    fi
}
