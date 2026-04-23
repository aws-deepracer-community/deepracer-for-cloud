#!/usr/bin/env bash
# DRoA (DeepRacer on AWS) shell functions.
# Sourced by bin/activate.sh alongside scripts_wrapper.sh and summary.sh.

function droa-list-models {
  dr-update-env && python3 "${DR_DIR}/scripts/droa/list_models.py" "$@"
}

function droa-get-model {
  dr-update-env && python3 "${DR_DIR}/scripts/droa/get_model.py" "$@"
}

#function droa-get-logs {
#  dr-update-env && python3 "${DR_DIR}/scripts/droa/get_logs.py" "$@"
#}

#function droa-trigger-evaluation {
#  dr-update-env && python3 "${DR_DIR}/scripts/droa/trigger_evaluation.py" "$@"
#}

#function droa-delete-model {
#  dr-update-env && python3 "${DR_DIR}/scripts/droa/delete_model.py" "$@"
#}

#function droa-import-model {
#  dr-update-env && python3 "${DR_DIR}/scripts/droa/import_model.py" "$@"
#}
