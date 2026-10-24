#!/bin/bash
# Builds ClipKeep.app (Apple Silicon + Intel) into ./build, plus ClipKeep.zip (used by
# the in-app updater) and ClipKeep.dmg (drag-to-install) for releases.
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
# App icon (Dock, Finder) and the menu bar template icon.
cp Resources/AppIcon.icns Resources/menubarTemplate.png Resources/menubarTemplate@2x.png "$app/Contents/Resources/"

# Ad-hoc signature so macOS can track its permissions (Accessibility, login item).
# Sign with the "ClipKeep Code Signing" certificate when this Mac has it: macOS then
# recognises every build as the same app, so permissions like Accessibility survive
# updates. Without it, fall back to ad hoc signing (permissions reset each update).
identity="${CLIPKEEP_SIGN_IDENTITY:-ClipKeep Code Signing}"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" "$app"
    echo "Signed with \"$identity\""
else
    codesign --force --sign - "$app"
    echo "Warning: \"$identity\" not found; signed ad hoc (Accessibility must be re-granted after each update)." >&2
fi

# Zip for GitHub releases; the in-app updater downloads this file.
ditto -c -k --keepParent "$app" build/ClipKeep.zip

version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
echo "Built $app and build/ClipKeep.zip (version $version)"

./make-dmg.sh
