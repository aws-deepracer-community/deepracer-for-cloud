#!/usr/bin/env bash
# DRoA (DeepRacer on AWS) shell functions.
# Sourced by bin/activate.sh alongside scripts_wrapper.sh and summary.sh.

function dr-droa-list-models {
  dr-update-env && python3 "${DR_DIR}/scripts/droa/list_models.py" "$@"
}

