#!/bin/sh
# Builds dist/LiveCue.app with embedded AppIcon and the bridge installer, signed ad hoc.
set -e
cd "$(dirname "$0")"

swift build -c release

# Assemble and sign in a temporary folder: synced folders such as an iCloud
# Desktop add file attributes that make codesign refuse the bundle.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/LiveCue.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/LiveCue "$APP/Contents/MacOS/LiveCue"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundle the audio-MacBook bridge installer (Connection → Get Bridge Installer).
sh tools/WINGLampBridge/build.sh >/dev/null
cp tools/WINGLampBridge/dist/WINGLampBridge.zip "$APP/Contents/Resources/WINGLampBridge.zip"

xattr -cr "$APP"
codesign --force --sign - --entitlements LiveCue.entitlements "$APP"

mkdir -p dist
rm -rf dist/LiveCue.app
ditto "$APP" dist/LiveCue.app
codesign --verify --deep --strict dist/LiveCue.app
echo "Built dist/LiveCue.app"
