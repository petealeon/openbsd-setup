#!/bin/sh
# ~/.xsession - started by xenodm
xrdb -merge "$HOME/.Xresources" 2>/dev/null
xsetroot -solid "#1a1b26" 2>/dev/null
exec spectrwm
