#!/bin/sh
# Run screenshots.el in a GUI Emacs on a virtual X display.  Not
# xvfb-run: as a container's first process it can hang for good.
set -e
Xvfb :99 -screen 0 2560x4000x24 -nolisten tcp &
for i in $(seq 100); do [ -e /tmp/.X11-unix/X99 ] && break; sleep 0.05; done
DISPLAY=:99 timeout 120 emacs -Q -l test/screenshots/screenshots.el \
  -f mayhem-screenshots-update-and-exit
