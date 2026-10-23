#!/bin/bash
# Packages build/ClipKeep.app into build/ClipKeep.dmg: a branded disk image with the app,
# a drag-to-install shortcut to Applications, custom volume icon, Gatekeeper guidance, and brand styling.
# Run ./build.sh first (it calls this script at the end).
set -euo pipefail
cd "$(dirname "$0")"

app="build/ClipKeep.app"
dmg="build/ClipKeep.dmg"
[ -d "$app" ] || { echo "Missing $app; run ./build.sh first." >&2; exit 1; }
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
volname="ClipKeep $version"

echo "Generating brand background for ClipKeep $version..."
swift Resources/DMG/generate-background.swift "$version" Resources/DMG

staging_dir="$(mktemp -d)"
staging_dmg="$staging_dir/staging.dmg"
trap 'rm -rf "$staging_dir"' EXIT

# Create a temporary writable HFS+ disk image
hdiutil create -size 120m -fs HFS+ -volname "$volname" "$staging_dmg" -ov -quiet

# Mount the temporary image
mount_info=$(hdiutil attach "$staging_dmg" -readwrite -noautoopen)
mount_vol=$(echo "$mount_info" | awk '/\/Volumes\//{print substr($0, index($0, "/Volumes/"))}')
vol_basename="$(basename "$mount_vol")"

cleanup_mount() {
    hdiutil detach "$mount_vol" -force -quiet 2>/dev/null || true
    rm -rf "$staging_dir"
}
trap cleanup_mount EXIT

# Copy app, Applications symlink, help guide, and background artwork
ditto "$app" "$mount_vol/ClipKeep.app"
ln -s /Applications "$mount_vol/Applications"
cp Resources/DMG/*.txt "$mount_vol/"
mkdir -p "$mount_vol/.background"
cp Resources/DMG/background.tiff "$mount_vol/.background/"

# Set custom volume icon so the mounted disk on Desktop/Sidebar displays the ClipKeep icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$mount_vol/.VolumeIcon.icns"
    SetFile -c icnC "$mount_vol/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$mount_vol" 2>/dev/null || true
    SetFile -a V "$mount_vol/.VolumeIcon.icns" 2>/dev/null || true
fi
SetFile -a V "$mount_vol/.background" 2>/dev/null || true

# Configure Finder window appearance and icon positions
osascript << APPLESCRIPT || echo "Warning: Finder styling skipped (headless?)" >&2
tell application "Finder"
    tell disk "$vol_basename"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 580} -- 660 x 460
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "ClipKeep.app" of container window to {160, 190}
        set position of item "Applications" of container window to {500, 190}
        set position of item "Can't open ClipKeep? Read me.txt" of container window to {500, 375}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Flush Finder changes and unmount
sync
sleep 1
hdiutil detach "$mount_vol" -quiet 2>/dev/null || hdiutil detach "$mount_vol" -force -quiet

# Convert to final compressed read-only DMG
rm -f "$dmg"
hdiutil convert "$staging_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg" -quiet
rm -rf "$staging_dir"
trap - EXIT

echo "Built $dmg (version $version) with brand styling and custom volume icon"
