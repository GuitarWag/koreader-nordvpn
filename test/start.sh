#!/bin/sh
rm -f /tmp/.X1-lock; Xvfb :1 -screen 0 800x1000x24 &
sleep 1
x11vnc -display :1 -forever -nopw -quiet &
websockify --web /usr/share/novnc 6080 localhost:5900 &
export DISPLAY=:1
exec /opt/bin/koreader
