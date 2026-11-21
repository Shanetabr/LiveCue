#!/bin/sh
# Builds the Intel + Apple Silicon bridge (macOS 11+) and packages it as
# dist/WINGLampBridge.zip inside this folder, ready to copy to the audio MacBook.
# Self-contained: works from a copy of this folder alone, without the rest of LiveCue.
set -e
cd "$(dirname "$0")"
OUT=dist/WINGLampBridge
rm -rf "$OUT" && mkdir -p "$OUT"
clang -O2 -Wall -Wno-deprecated-declarations -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
  -framework CoreFoundation -framework CoreMIDI bridge.c -o "$OUT/wing-lamp-bridge"
codesign --force -s - "$OUT/wing-lamp-bridge"
cp "Install WING Lamp Bridge.command" "Uninstall WING Lamp Bridge.command" "Test Lamp Flash.command" README.md "$OUT/"
chmod +x "$OUT"/*.command
(cd dist && rm -f WINGLampBridge.zip && ditto -c -k --norsrc --noextattr --keepParent WINGLampBridge WINGLampBridge.zip)
echo "Built $(pwd)/dist/WINGLampBridge.zip"
