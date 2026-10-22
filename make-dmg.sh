#!/bin/bash
# Packages build/ClipKeep.app into build/ClipKeep.dmg: a disk image with the app
# and a shortcut to Applications, so installing is a single drag.
# Run ./build.sh first (it calls this script at the end).
set -euo pipefail
cd "$(dirname "$0")"

app="build/ClipKeep.app"
dmg="build/ClipKeep.dmg"
[ -d "$app" ] || { echo "Missing $app; run ./build.sh first." >&2; exit 1; }
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/ClipKeep.app"
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
hdiutil create -quiet -volname "ClipKeep $version" -srcfolder "$staging" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg"

echo "Built $dmg (version $version)"
