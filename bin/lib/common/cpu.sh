#!/usr/bin/env bash

# Library for CPU functions
#
# This file is sourced by the main script and contains functions that are specific to custom utilities.
# It is sourced after the common libraries and before the main script.

# CPU Functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

function get_cpu_level() {
  # Function to detect the CPU level

    if [[ -f /proc/cpuinfo ]] && [[ "$(cat /proc/cpuinfo | grep avx2 | wc -l)" > 0 ]]; then
        echo "cpu-avx2"
    elif [[ "$(type sysctl 2> /dev/null)" ]] && [[ "$(sysctl -n hw.optional.avx2_0)" == 1 ]]; then
        echo "cpu-avx2"
    fi
}

function check_intel_cpu() {
  # Function to detect if the CPU is Intel
  log_message warning "On non intel systems you may see: sysctl: cannot stat /proc/sys/machdep/cpu/vendor: No such file or directory, this is safe to ignore"

  if [[ -f /proc/cpuinfo ]] && [[ "$(cat /proc/cpuinfo | grep GenuineIntel | wc -l)" > 0 ]]; then
      return 0 # CPU is Intel, return true
  elif [[ "$(type sysctl 2> /dev/null)" ]] && [[ "$(sysctl -n machdep.cpu.vendor)" == "GenuineIntel" ]]; then
      return 0 # CPU is Intel, return true
  else
      return 1 # CPU is not Intel, return false
  fi
}

