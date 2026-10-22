#!/bin/bash
# Builds ClipKeep.app into ./build. Needs only Apple's Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

app="build/ClipKeep.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClipKeep" "$app/Contents/MacOS/ClipKeep"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signature so macOS can track its permissions (Accessibility, login item).
codesign --force --sign - "$app"

echo "Built $app"
