#!/bin/bash

current=$(hyprctl getoption general:layout -j | jq -r '.str')

if [ "$current" = "dwindle" ]; then
    hyprctl keyword general:layout "master"
else
    hyprctl keyword general:layout "dwindle"
fi
