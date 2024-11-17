#!/usr/bin/env bash
# This script uploads the latest DeepRacer model and activates the necessary environment.
# It processes command line options to customize the environment file path, enable local upload, and specify an evaluation environment file.
# After processing the options, it activates the environment, uploads the model, and updates the evaluation environment file with the new model prefix if specified.
#
# Usage:
# ./upload-rotate.sh [-e <environment file>] [-L] [-E <evaluation environment file>] [-c <counter file>] [-v]
#
# Options:
# -c <counter file>               Specify the path to the counter file. This is optional.
# -e <environment file>           Specify the path to the environment configuration file. Defaults to 'run.env' in the script's directory.
# -L                              Enable local upload. This option does not require a value.
# -v                              Add more verbose logging, capturing iteration and entropy numbers.
# -E <evaluation environment file> Specify the path to the evaluation environment configuration file. This is optional.
# -C                              Upload the car file. This option does not require a value.
#
# Example:
# ./upload-rotate.sh -e custom.env -L -E eval.env
#
# To run this script manually, navigate to its directory and execute it with desired options.
# Ensure you have the necessary permissions to execute the script.

# Navigate to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DR_DIR="$(dirname "$SCRIPT_DIR")"

# Default environment file path
ENV_FILE="$DR_DIR/run.env"
LOCAL_UPLOAD=""
EVAL_ENV_FILE=""

# Process command line options
while getopts "e:LE:vc:C" opt; do
  case $opt in
    c) COUNTER_FILE="$OPTARG" ;;
    e) ENV_FILE="$OPTARG" ;;
    L) LOCAL_UPLOAD="-L" ;;
    E) EVAL_ENV_FILE="$OPTARG" ;;
    v) VERBOSE_LOGGING="true" ;;
    C) CAR_FILE="-C" ;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done

# If a counter file is specified, increment the counter
if [ -n "$COUNTER_FILE" ]; then
  if [ -f "$COUNTER_FILE" ]; then
    COUNTER=$(cat "$COUNTER_FILE")
    COUNTER=$((COUNTER + 1))
    echo "$COUNTER" > "$COUNTER_FILE"
    export UPLOAD_COUNTER=$COUNTER
  else
    echo "Error: Counter file '$COUNTER_FILE' not found." >&2
    exit 1
  fi
fi

# Activate the environment
if [ -f "$ENV_FILE" ]; then
  source "$DR_DIR/bin/activate.sh" "$ENV_FILE"
else
  if [ -f "$DR_DIR/$ENV_FILE" ]; then
    source "$DR_DIR/bin/activate.sh" "$DR_DIR/$ENV_FILE"
  else
    echo "Error: Environment file '$ENV_FILE' not found." >&2
    exit 1
  fi
fi

# Execute the upload command
if [ -n "$COUNTER_FILE" ]; then
  dr-upload-model $LOCAL_UPLOAD -f
else
  dr-upload-model $LOCAL_UPLOAD -1 -f
fi
dr-update

# If the car file option is specified, upload the car file
if [ -n "$CAR_FILE" ]; then
  dr-upload-car-zip $LOCAL_UPLOAD -f
fi

# If an evaluation environment file is specified then alter the model prefix to enable evaluation
if [ -n "$EVAL_ENV_FILE" ]; then
  if [ ! -f "$EVAL_ENV_FILE" ]; then
    if [ -f "$DR_DIR/$EVAL_ENV_FILE" ]; then
      EVAL_ENV_FILE="$DR_DIR/$EVAL_ENV_FILE"
    else
      echo "Error: Evaluation environment file '$EVAL_ENV_FILE' not found." >&2
      exit 1
    fi
  fi
  MODEL_PREFIX=$(echo $DR_UPLOAD_S3_PREFIX)
  echo "Updating evaluation environment file $EVAL_ENV_FILE to use $MODEL_PREFIX"
  sed -i "s/DR_LOCAL_S3_MODEL_PREFIX=.*/DR_LOCAL_S3_MODEL_PREFIX=$MODEL_PREFIX/" $EVAL_ENV_FILE
fi

printf "\n############################################################\n"
printf "### %-15s %-15s\n" "Configuration:" "$ENV_FILE"
printf "### %-15s %-15s\n" "Model Name:" "$DR_LOCAL_S3_MODEL_PREFIX"
printf "### %-15s %-15s\n" "Uploaded Model:" "$DR_UPLOAD_S3_PREFIX"

# If verbose logging is enabled, retrieve the entropy and iteration numbers.
if [ -n "$VERBOSE_LOGGING" ]; then
  CONTAINER_ID=$(docker ps -f "name=deepracer-${DR_RUN_ID}_rl_coach" --format "{{.ID}}")
  if [ -n "$CONTAINER_ID" ]; then
    LAST_ITERATION=$(docker logs --since 20m "$CONTAINER_ID" 2>/dev/null | awk '{if (match($0, /Best checkpoint number: ([0-9]+), Last checkpoint number: ([0-9]+)/, arr)) {print arr[2]}}' | tail -n 1)
    printf "### %-15s %-15s\n" "Last iteration:" "$LAST_ITERATION"

    ENTROPY=$(docker logs --since 20m "$CONTAINER_ID" 2>/dev/null | awk '{if (match($0, /Entropy=([0-9.]+)/, arr)) {print arr[1]}}' | tail -n 1)
    printf "### %-15s %-15s\n" "Entropy:" "$ENTROPY"
  fi
fi

printf "### %-15s %-15s\n" "Completed at:" "$(date)"
printf "############################################################\n\n"
