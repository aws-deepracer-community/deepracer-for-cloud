#!/bin/bash

set -e

if [[ $EUID == 0 ]]; then
    echo "ERROR: Do not run as root / via sudo."
    exit 1
fi

if [ -z "$DR_DIR" ]; then
    echo "ERROR: DR_DIR not set. Run 'source bin/activate.sh' before start-xorg.sh."
    exit 1
fi

if [ -z "$DR_DISPLAY" ]; then
    echo "ERROR: DR_DISPLAY not set. Ensure the variable is configured in system.env."
    exit 1
fi

sudo touch $DR_DIR/tmp/xorg.log

screen -dmS DeepracerXorg
screen -r DeepracerXorg -X stuff $'sudo xinit /usr/bin/mwm -display $DR_DISPLAY -- /usr/lib/xorg/Xorg $DR_DISPLAY -config $DR_DIR/tmp/xorg.conf > $DR_DIR/tmp/xorg.log 2>&1 &\n'

sleep 1

if [[ "${DR_GUI_ENABLE,,}" == "true" ]]; then
    xrandr -s 1400x900
    x11vnc -bg -forever -no6 -nopw -rfbport 5901 -rfbportv6 -1 -loop -display WAIT$DR_DISPLAY &
    sleep 1
fi

xauth generate $DR_DISPLAY

if timeout 1s xset -display $DR_DISPLAY q &>/dev/null; then
    echo "X Server started on display $DR_DISPLAY"
else
    echo "Server failed to start on display $DR_DISPLAY"
fi
