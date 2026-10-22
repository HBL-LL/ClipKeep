#!/bin/bash
# Builds ClipKeep.app (Apple Silicon + Intel) into ./build, plus ClipKeep.zip for releases.
# Needs only Apple's Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

arch_flags=(--arch arm64 --arch x86_64)
swift build -c release "${arch_flags[@]}"
bin_path="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

app="build/ClipKeep.app"
rm -rf "$app" build/ClipKeep.zip
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/ClipKeep" "$app/Contents/MacOS/ClipKeep"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signature so macOS can track its permissions (Accessibility, login item).
codesign --force --sign - "$app"

# Zip for GitHub releases; the in-app updater downloads this file.
ditto -c -k --keepParent "$app" build/ClipKeep.zip

version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
echo "Built $app and build/ClipKeep.zip (version $version)"
