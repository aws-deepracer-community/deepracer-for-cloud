#!/usr/bin/env bash

# Library for CLI functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# CLI Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

function confirm() {
    local message="$1"
    log_message debug "Confirming: ${message}"
    read -p "${message} [y/N]: " response
    case "${response}" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}