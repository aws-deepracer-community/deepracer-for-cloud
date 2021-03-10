#!/bin/bash
source /home/ubuntu/deepracer-for-cloud/bin/activate.sh
$DR_DIR/utils/submit-monitor.py -m March-H2B-B-7-4 -b 86eb6d2e-72ad-4443-8b40-fb67514f5afe -s -l $@
