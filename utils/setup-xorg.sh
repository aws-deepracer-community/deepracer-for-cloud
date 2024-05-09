#!/bin/bash

set -e

# Script to install basic X-Windows on a headless instance (e.g. in EC2)

# Script shall run as user, not root. Sudo will be used when needed.
if [[ $EUID == 0 ]]; then
    echo "ERROR: Do not run as root / via sudo."
    exit 1
fi

# Deepracer environment variables must be set.
if [ -z "$DR_DIR" ]; then
    echo "ERROR: DR_DIR not set. Run 'source bin/activate.sh' before setup-xorg.sh."
    exit 1
fi

# Install additional packages
sudo apt-get install xinit xserver-xorg-legacy x11-xserver-utils x11-utils \
        menu mesa-utils xterm mwm x11vnc pkg-config screen -y --no-install-recommends

# Configure
sudo sed -i -e "s/console/anybody/" /etc/X11/Xwrapper.config
BUS_ID=$(nvidia-xconfig --query-gpu-info | grep "PCI BusID" | cut -f2- -d: | sed -e 's/^[[:space:]]*//' | head -1)
sudo nvidia-xconfig --busid=$BUS_ID -o $DR_DIR/tmp/xorg.conf

touch ~/.Xauthority

sudo tee -a $DR_DIR/tmp/xorg.conf <<EOF

Section "DRI"
        Mode 0666
EndSection
EOF
