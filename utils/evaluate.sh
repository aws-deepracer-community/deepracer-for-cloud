#!/bin/bash

# This script evaluates DeepRacer models by managing the evaluation process.
# It requires one argument: the path to the environment configuration file.
# The script sources environment variables from the specified file, then:
# 1. Validates the existence of the environment file.
# 2. Sources the activate.sh script to set up necessary environment variables.
# 3. Prints the evaluation configuration, including Run ID, Model Name, and Track.
# 4. Executes the evaluation process by stopping any ongoing evaluation, and starts a new evaluation.

# To run this script every 3 minutes using crontab, follow these steps:
# 1. Open the crontab editor by executing `crontab -e` in your terminal.
# 2. Add the following line to schedule the script:
#    `*/3 * * * * <DRFC_PATH>/utils/evaluate.sh run.env >> <LOG_PATH>/evaluate.log 2>&1`
# 3. Save and close the editor. The script is now scheduled to run every 3 minutes.

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <environment file>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DR_DIR="$(dirname $SCRIPT_DIR)"
ENV_FILE="$1"

if [[ -f "$DR_DIR/$ENV_FILE" ]]; then
  source $DR_DIR/bin/activate.sh $DR_DIR/$ENV_FILE
else
  echo "File $ENV_FILE does not exist."
  exit 1
fi

printf "\n##################################################\n"
printf "### %-15s %-15s\n" "Configuration:" "$ENV_FILE"
printf "### %-15s %-15s\n" "Run ID:" "$DR_RUN_ID"
printf "### %-15s %-15s\n" "Model Name:" "$DR_LOCAL_S3_MODEL_PREFIX"
printf "### %-15s %-15s\n" "Track:" "$DR_WORLD_NAME"
printf "### %-15s %-15s\n" "Start:" "$(date)"
printf "##################################################\n\n"

dr-stop-evaluation

# Check if Docker style is set to swarm and wait for all containers to stop
if [ "$DR_DOCKER_STYLE" == "swarm" ]; then
	STACK_NAME="deepracer-eval-$DR_RUN_ID"
	STACK_CONTAINERS=$(docker stack ps $STACK_NAME 2>/dev/null | wc -l)
	while [[ "$STACK_CONTAINERS" -gt 1 ]]; do
		echo "Waiting for all containers in the stack to stop..."
		sleep 5
		STACK_CONTAINERS=$(docker stack ps $STACK_NAME 2>/dev/null | wc -l)
	done
fi

dr-start-evaluation -q
