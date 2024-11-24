#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DR_DIR="$(dirname $SCRIPT_DIR)"
ENV_FILE="$1"

source $DR_DIR/bin/activate.sh $DR_DIR/$1
dr-stop-training