#!/bin/bash
# Stops WING Lamp Bridge and removes it from this Mac. The log file is kept.
LABEL=com.livecue.winglampbridge
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/WINGLampBridge"
echo "WING Lamp Bridge is stopped and removed."
read -n 1 -s -r -p "Press any key to close."
