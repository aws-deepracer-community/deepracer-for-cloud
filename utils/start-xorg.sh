#!/bin/bash
export DISPLAY=:0
touch ~/.Xauthority
export XAUTHORITY=~/.Xauthority

nohup xinit /usr/bin/jwm &
sleep 1
xrandr -s 1400x900
x11vnc -bg -forever -nopw -rfbport 5900 -display WAIT$DISPLAY & 
sleep 1
