#!/bin/sh
# Builds dist/LiveCue.app with embedded AppIcon, signed ad hoc.
set -e
cd "$(dirname "$0")"

swift build -c release
APP=dist/LiveCue.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/LiveCue "$APP/Contents/MacOS/LiveCue"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - --entitlements LiveCue.entitlements "$APP"
echo "Built $APP"
