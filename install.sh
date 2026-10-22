#!/bin/bash
# Installs the latest ClipKeep release into /Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Hamza-Boulila/ClipKeep/main/install.sh | bash
#
# Downloading with curl skips the "could not verify" warning macOS shows for apps
# downloaded in a browser that aren't signed with a paid Apple Developer ID.
# The download is checked against GitHub's SHA-256, the app's identity, and its
# code signature before anything is installed.
set -euo pipefail

repo="Hamza-Boulila/ClipKeep"
bundle_id="local.clipkeep"
dest="${CLIPKEEP_INSTALL_DIR:-/Applications}"

fail() { printf '\nClipKeep install failed: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "ClipKeep runs on macOS only."
if [ ! -w "$dest" ]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Finding the latest ClipKeep release…"
json="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo/releases/latest")" \
    || fail "couldn't reach GitHub. Check your internet connection."
read_json() { plutil -extract "$1" raw -o - - <<<"$json" 2>/dev/null; }

version="$(read_json tag_name)" || fail "the release information was unreadable."
version="${version#v}"
url="" digest=""
count="$(read_json assets)" || count=0
for ((i = 0; i < count; i++)); do
    if [ "$(read_json "assets.$i.name")" = "ClipKeep.zip" ]; then
        url="$(read_json "assets.$i.browser_download_url")"
        digest="$(read_json "assets.$i.digest" || true)"
        break
    fi
done
[ -n "$url" ] || fail "the latest release has no ClipKeep.zip."

echo "Downloading ClipKeep $version…"
curl -fsSL -o "$work/ClipKeep.zip" "$url" || fail "the download didn't complete."

if [ -n "$digest" ]; then
    actual="sha256:$(shasum -a 256 "$work/ClipKeep.zip" | cut -d' ' -f1)"
    [ "$actual" = "$digest" ] || fail "the download doesn't match its checksum."
fi

ditto -x -k "$work/ClipKeep.zip" "$work/unpacked" || fail "the download couldn't be unzipped."
app="$work/unpacked/ClipKeep.app"
[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" 2>/dev/null)" = "$bundle_id" ] \
    || fail "the download isn't ClipKeep."
codesign --verify --deep --strict "$app" 2>/dev/null || fail "the app's code signature is broken."

# Quit a copy already running from the install location, then replace it.
target="$dest/ClipKeep.app"
if pgrep -f "$target/Contents/MacOS/ClipKeep" >/dev/null; then
    echo "Quitting the running ClipKeep…"
    pkill -f "$target/Contents/MacOS/ClipKeep" || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$target/Contents/MacOS/ClipKeep" >/dev/null || break
        sleep 0.3
    done
fi
rm -rf "$target"
ditto "$app" "$target" || fail "couldn't copy ClipKeep into $dest."

echo "Installed ClipKeep $version in $dest."
if [ -z "${CLIPKEEP_NO_LAUNCH:-}" ]; then
    open "$target"
    echo "ClipKeep is running: look for its icon in the menu bar, or press ⇧⌘V."
fi
