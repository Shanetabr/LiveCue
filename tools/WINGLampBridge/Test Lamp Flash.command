#!/bin/bash
# Flashes the WING lamp for 3 seconds straight over USB from this Mac, then turns it off.
# Uses the installed copy if there is one, otherwise the one in this folder.
BIN="$HOME/Library/Application Support/WINGLampBridge/wing-lamp-bridge"
[ -x "$BIN" ] || BIN="$(dirname "$0")/wing-lamp-bridge"
"$BIN" --list
echo
"$BIN" --flash
echo
read -n 1 -s -r -p "Press any key to close."
