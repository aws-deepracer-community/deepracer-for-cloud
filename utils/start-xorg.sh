#!/bin/bash
export DISPLAY=$DR_DISPLAY

nohup sudo xinit /usr/bin/jwm -- /usr/lib/xorg/Xorg $DISPLAY -config $DR_DIR/tmp/xorg.conf > $DR_DIR/tmp/xorg.log 2>&1 &
sleep 1

if [[ "${DR_GUI_ENABLE,,}" == "true" ]]; then   
    xrandr -s 1400x900
    x11vnc -bg -forever -no6 -nopw -rfbport 5901 -rfbportv6 -1 -loop -display WAIT$DISPLAY & 
    sleep 1
fi

xauth generate $DISPLAY
export XAUTHORITY=~/.Xauthority

if timeout 1s xset q &>/dev/null; then 
    echo "X Server started on display $DISPLAY" 
else
    echo "Server failed to start on display $DISPLAY"
fi