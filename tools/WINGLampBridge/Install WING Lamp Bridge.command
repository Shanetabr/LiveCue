#!/bin/bash
# Installs WING Lamp Bridge on this Mac (the audio MacBook connected to the WING by USB).
# It starts in the background at every login and restarts itself if it stops.
set -e
cd "$(dirname "$0")"

LABEL=com.livecue.winglampbridge
APP_DIR="$HOME/Library/Application Support/WINGLampBridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/WINGLampBridge.log"

[ -f wing-lamp-bridge ] || { echo "wing-lamp-bridge is missing from this folder."; exit 1; }

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp wing-lamp-bridge "$APP_DIR/"
xattr -cr "$APP_DIR/wing-lamp-bridge" 2>/dev/null || true
codesign --force -s - "$APP_DIR/wing-lamp-bridge" >/dev/null 2>&1 || true
chmod +x "$APP_DIR/wing-lamp-bridge"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP_DIR/wing-lamp-bridge</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$UID" "$PLIST"
sleep 2

echo
echo "WING Lamp Bridge is installed and running."
echo "It starts by itself every time this Mac logs in."
echo
echo "Turn OFF both Live routings in Audio MIDI Setup (set them to blank),"
echo "so the lamp is not sent twice."
echo
echo "Recent log ($LOG):"
tail -n 8 "$LOG" 2>/dev/null || true
echo
read -n 1 -s -r -p "Press any key to close."
