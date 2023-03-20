#!/usr/bin/env bash

# Library for Environment functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# Environment Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script
# If you use this module, you need to define it after logging.sh

function var_export() {
    local varname=$1

    # Export variable
    log_message debug "Special Exporting variable: $( eval echo "$varname" )"
    eval "export \"${varname?}\""
}