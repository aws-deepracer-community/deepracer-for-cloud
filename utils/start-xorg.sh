#!/bin/bash

set -e

# Script shall run as user, not root. Sudo will be used when needed.
if [[ $EUID == 0 ]]; then
    echo "ERROR: Do not run as root / via sudo."
    exit 1
fi

# X must not be running when we try to start it.
if timeout 1s xset -display $DR_DISPLAY q &>/dev/null; then
    echo "ERROR: X Server already running on display $DR_DISPLAY."
    exit 1
fi

# Deepracer environment variables must be set.
if [ -z "$DR_DIR" ]; then
    echo "ERROR: DR_DIR not set. Run 'source bin/activate.sh' before start-xorg.sh."
    exit 1
fi

if [ -z "$DR_DISPLAY" ]; then
    echo "ERROR: DR_DISPLAY not set. Ensure the variable is configured in system.env."
    exit 1
fi

# Start inside a sudo-screen to prevent it from stopping when disconnecting terminal.
sudo screen -d -S DeepracerXorg -m bash -c "xinit /usr/bin/mwm -display $DR_DISPLAY -- /usr/lib/xorg/Xorg $DR_DISPLAY -config $DR_DIR/tmp/xorg.conf > $DR_DIR/tmp/xorg.log 2>&1"

# Screen detaches; let it have some time to start X.
sleep 1

if [[ "${DR_GUI_ENABLE,,}" == "true" ]]; then
    x11vnc -bg -forever -no6 -nopw -rfbport 5901 -rfbportv6 -1 -loop -display WAIT$DR_DISPLAY &
    sleep 1
fi

# Create xauth mit-magic-cookie.
xauth generate $DR_DISPLAY

# Check if X started successfully. If not, print error message and exit.
if timeout 1s xset -display $DR_DISPLAY q &>/dev/null; then
    echo "X Server started on display $DR_DISPLAY"
else
    echo "Server failed to start on display $DR_DISPLAY"
fi
