# ClipKeep

A small menu bar clipboard manager for macOS 14+.

## Install

1. Download `ClipKeep.dmg` from the [latest release](https://github.com/Hamza-Boulila/ClipKeep/releases/latest) and open it.
2. Drag **ClipKeep** onto the **Applications** folder next to it.
3. Open ClipKeep from Applications. The first time, right-click it and choose **Open**. ClipKeep isn't notarized by Apple, so macOS asks once. If it still won't open, go to System Settings → Privacy & Security and click **Open Anyway**.

Works on Apple Silicon and Intel Macs running macOS 14 or later.

## Updates

ClipKeep checks GitHub for a new release once a day (Settings → Updates; you can turn this off). You can also click **Check for Updates** there, or right-click the menu bar icon. When a new version is out, ClipKeep shows what changed and can download, check, and install it, then relaunch.

ClipKeep has to be somewhere it can replace itself, such as your Applications folder. After an update, macOS may ask you to allow Accessibility access again.

## Use it

- **Click the menu bar icon** to open your clipboard history under it, or press **⇧⌘V** to open it near the mouse.
- **Right-click the icon** for Pause Recording, Clear History and Quit. The **gear** in the history window opens Settings.
- Type to search. Use **↑ ↓** to move, **↩** or a click to paste, **⌘1–⌘9** to paste one of the first nine clips.
- **⌘P** pins a clip (pinned clips are never trimmed), **⌘⌫** deletes one, **esc** closes the window.
- Copied images (screenshots, pictures) are saved too and show as thumbnails. Type "image" to find them.
- Settings: history size, saving images, launch at login, plain-text pasting, and apps to ignore.

To paste for you, ClipKeep needs **Accessibility** access (System Settings → Privacy & Security → Accessibility). Without it, the clip is copied and you press ⌘V yourself.

## How it works

| Part | File | What it does |
| --- | --- | --- |
| Clipboard watcher | `ClipboardMonitor.swift` | Checks the clipboard's change counter every 0.5 s. Saves plain text plus rich text (RTF, or HTML converted to RTF); when a copy has no text, saves its image (up to 50 MB). Skips password-manager content, ignored apps, blank text, file copies' icons and its own pastes. |
| History | `ClipStore.swift` | Newest first; copying the same text or image again moves it to the top. Keeps the last N unpinned clips. Saved to `~/Library/Application Support/ClipKeep/history.json`, with images as PNG files in `images/` next to it (owner-only permissions). |
| Images | `ImageSupport.swift` | Converts copied images to PNG off the main thread, matches repeats by their pixels, and makes cached thumbnails for the list. |
| Popup window | `PanelController.swift`, `ClipListView.swift` | A floating panel that takes typing without stealing focus from the app you're in, so the paste lands there. |
| Paste | `Paster.swift` | Writes the clip to the clipboard and sends ⌘V. |
| Hotkey | `HotKey.swift` | System-wide ⇧⌘V via Carbon's `RegisterEventHotKey`. |
| Updates | `UpdateCore.swift`, `Updater.swift` | Reads the latest GitHub release, downloads `ClipKeep.zip`, checks its SHA-256, bundle ID, version and code signature, swaps the app in place (rolling back on failure) and relaunches. |

## Build

Needs only Apple's Command Line Tools (no Xcode):

```bash
./build.sh
open build/ClipKeep.app
```

This makes `build/ClipKeep.app`, `build/ClipKeep.zip` and `build/ClipKeep.dmg` (Apple Silicon + Intel). `./make-dmg.sh` repackages an existing build as a DMG without rebuilding.

The app is signed ad hoc, so macOS treats every rebuild as a new app: after rebuilding, turn ClipKeep's Accessibility permission off and on again.

## License

MIT. See [LICENSE](LICENSE).
