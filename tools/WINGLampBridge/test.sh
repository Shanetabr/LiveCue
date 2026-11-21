#!/bin/sh
# Builds the bridge and runs the virtual-port integration test. No console is addressed.
set -e
cd "$(dirname "$0")"
clang -Wall -Wno-deprecated-declarations -framework CoreFoundation -framework CoreMIDI bridge.c -o /tmp/wing-lamp-bridge
clang -Wall -Wno-deprecated-declarations -framework CoreFoundation -framework CoreMIDI test.c -o /tmp/wing-lamp-bridge-test
/tmp/wing-lamp-bridge-test /tmp/wing-lamp-bridge
