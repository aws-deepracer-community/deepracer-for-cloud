#!/usr/bin/env bash

# Library for Docker functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# Docker Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script
# logging needs to be imported first
# utilities needs to be imported second
# cli needs to be imported third

function pull_docker_image() {
  # Function to pull a Docker image if it is not already available

    local image_name="$1"
    local tag="$2"
    log_message debug "Checking if Docker image ${image_name}:${tag} is available..."
    if docker image inspect "${image_name}:${tag}" > /dev/null 2>&1; then
        log_message info "Docker image ${image_name}:${tag} is already available."
    else
        log_message warning "Docker image ${image_name}:${tag} not found. Attempting to pull, this may take a while..."
        emit_cmd docker pull "${image_name}:${tag}"
        if docker image inspect "${image_name}:${tag}" > /dev/null 2>&1; then
            log_message info "Docker image ${image_name}:${tag} successfully pulled."
        else
            log_message error "Failed to pull Docker image ${image_name}:${tag}. Exiting..."
            exit 1
        fi
    fi
}

function docker_swarm_init() {
  # Function to initialize Docker Swarm mode if it is not already enabled

    if docker node ls > /dev/null 2>&1; then
        log_message warning "Swarm mode already enabled."
    else
        log_message warning "Swarm mode not enabled. Initializing swarm..."
        emit_cmd docker swarm init
        if docker node ls > /dev/null 2>&1; then
            log_message info "Swarm mode successfully enabled."
        else
            log_message error "Failed to enable Swarm mode. Exiting..."
            exit 1
        fi
    fi
}

function setup_swarm_network() {
    local sagemaker_network="$1"
    local swarm_node
    swarm_node="$(docker node inspect self | jq .[0].ID -r)"

    log_message info "Updating Swarm node labels..."
    docker node update --label-add Sagemaker=true "$swarm_node" > /dev/null 2> /dev/null
    docker node update --label-add Robomaker=true "$swarm_node" > /dev/null 2> /dev/null

    log_message info "Creating SageMaker network if it doesn't exist..."
    if ! docker network ls | grep -q "$sagemaker_network"; then
        emit_cmd docker network create "$sagemaker_network" -d overlay --attachable --scope swarm --subnet=192.168.2.0/24
    else
        log_message warning "SageMaker network already exists."
        if confirm "Do you want to recreate it?"; then
          log_message info "User confirmed, deleting and recreating swarm network."
          emit_cmd docker network rm "$sagemaker_network"
          emit_cmd docker network create "$sagemaker_network" -d overlay --attachable --scope swarm --subnet=192.168.2.0/24

        else
          log_message warning "User did not confirm, Skipping network creation."
        fi
    fi
}

function check_and_start_docker() {
  # Check if Docker runs -- if not, then start it.

  if [[ "$(type service 2> /dev/null)" ]]; then
    if ! service docker status > /dev/null; then
      sudo service docker start
      log_message info "Docker daemon started."
    else
      log_message info "Docker daemon already running."
    fi
  fi
}

function set_docker_style() {
  # Set the Docker style to either "default" or "swarm"

  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    log_message info "Setting DR_DOCKER_FILE_SEP to 'swarm'"
    export DR_DOCKER_FILE_SEP="-c"
    SWARM_NODE=$(docker node inspect self | jq .[0].ID -r)
    log_message debug "Swarm node ID: $SWARM_NODE"

    SWARM_NODE_UPDATE=$(docker node update --label-add Sagemaker=true $SWARM_NODE)
    log_message debug "Swarm node update: $SWARM_NODE_UPDATE"
  else
    log_message info "Setting DR_DOCKER_FILE_SEP to 'default'"
    export DR_DOCKER_FILE_SEP="-f"
  fi
}



