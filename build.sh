#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sticky Note.app"
BINARY="$APP/Contents/MacOS/StickyNote"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

# Build for Apple Silicon and Intel, then merge into one universal binary.
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos13.0" \
    Sources/*.swift \
    -o "build/StickyNote-$arch"
done
lipo -create build/StickyNote-arm64 build/StickyNote-x86_64 -output "$BINARY"
rm build/StickyNote-arm64 build/StickyNote-x86_64

codesign --force --sign - "$APP"

echo "Built $APP"
