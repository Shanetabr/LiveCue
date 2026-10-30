#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CHECK_BINARY=$(mktemp -t livecue-memory-check)
trap 'rm -f "$CHECK_BINARY"' EXIT
swiftc -parse-as-library -strict-concurrency=complete \
  Sources/Talkback/Line.swift Sources/Talkback/TranscriptArchive.swift \
  Sources/Talkback/TranscriptExporter.swift Sources/Talkback/AudioCapture.swift \
  Sources/Talkback/Transcriber.swift Tests/MemoryChecks.swift -o "$CHECK_BINARY"
"$CHECK_BINARY"
