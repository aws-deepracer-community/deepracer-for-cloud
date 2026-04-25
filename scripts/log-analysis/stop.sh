#!/usr/bin/env bash

echo "Stopping log-analysis container..."
if docker stop deepracer-analysis > /dev/null 2>&1; then
  echo "Log-analysis stopped."
else
  echo "Log-analysis is not running."
fi
