#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sticky Note.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/StickyNote.swift \
  -o "$APP/Contents/MacOS/StickyNote"

codesign --force --sign - "$APP"

echo "Built $APP"
