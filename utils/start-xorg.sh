#!/bin/bash
export DISPLAY=:0

nohup xinit /usr/bin/jwm &
sleep 1
xrandr -s 1400x900
x11vnc -bg -forever -no6 -nopw -rfbport 5901 -rfbportv6 -1 -loop -display WAIT$DISPLAY & 
sleep 1

xauth generate $DISPLAY
export XAUTHORITY=~/.Xauthority
