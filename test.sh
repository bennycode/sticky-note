#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# The checklist without the app around it, so the quadrant moves can be checked on their own.
swiftc -target "$(uname -m)-apple-macos13.0" \
  Sources/Note.swift Sources/ChecklistView.swift Sources/NoteWindow.swift Tests/main.swift \
  -o build/checklist-test
build/checklist-test
