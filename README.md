# ClipKeep

A small menu bar clipboard manager for macOS 14+.

## Use it

- **⇧⌘V** opens your clipboard history near the mouse. You can also use the menu bar icon, or open the app again.
- Type to search. Use **↑ ↓** to move, **↩** or a click to paste, **⌘1–⌘9** to paste one of the first nine clips.
- **⌘P** pins a clip (pinned clips are never trimmed), **⌘⌫** deletes one, **esc** closes the window.
- Settings (menu bar icon → Settings…): history size, launch at login, plain-text pasting, and apps to ignore.

To paste for you, ClipKeep needs **Accessibility** access (System Settings → Privacy & Security → Accessibility). Without it, the clip is copied and you press ⌘V yourself.

## How it works

| Part | File | What it does |
| --- | --- | --- |
| Clipboard watcher | `ClipboardMonitor.swift` | Checks the clipboard's change counter every 0.5 s. Saves plain text plus rich text (RTF, or HTML converted to RTF). Skips password-manager content, ignored apps, blank text and its own pastes. |
| History | `ClipStore.swift` | Newest first; copying the same text again moves it to the top. Keeps the last N unpinned clips. Saved to `~/Library/Application Support/ClipKeep/history.json` (owner-only permissions). |
| Popup window | `PanelController.swift`, `ClipListView.swift` | A floating panel that takes typing without stealing focus from the app you're in, so the paste lands there. |
| Paste | `Paster.swift` | Writes the clip to the clipboard and sends ⌘V. |
| Hotkey | `HotKey.swift` | System-wide ⇧⌘V via Carbon's `RegisterEventHotKey`. |

## Build

Needs only Apple's Command Line Tools (no Xcode):

```bash
./build.sh
open build/ClipKeep.app
```

The app is signed ad hoc, so macOS treats every rebuild as a new app: after rebuilding, turn ClipKeep's Accessibility permission off and on again.

## License

MIT. See [LICENSE](LICENSE).
