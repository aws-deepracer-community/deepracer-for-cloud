#!/bin/bash
export DISPLAY=$DR_DISPLAY

nohup sudo  xinit /usr/bin/jwm -- /usr/lib/xorg/Xorg $DISPLAY -config $DR_DIR/tmp/xorg.conf &
sleep 1

if [[ "${DR_GUI_ENABLE,,}" == "true" ]]; then   
    xrandr -s 1400x900
    x11vnc -bg -forever -no6 -nopw -rfbport 5901 -rfbportv6 -1 -loop -display WAIT$DISPLAY & 
    sleep 1
fi

xauth generate $DISPLAY
export XAUTHORITY=~/.Xauthority
