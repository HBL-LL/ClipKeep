import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A floating panel that takes keyboard focus without making ClipKeep the active app,
/// so the app you were typing in stays in front and receives the paste.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var selection = 0
    /// Bumped each time the panel opens so the search field takes focus again.
    @Published var focusToken = 0
    /// True while the "delete all clips?" confirmation bar is showing.
    @Published var confirmingClear = false
    /// The clip being edited, while the editor is showing, and its edited text.
    @Published var editingID: UUID?
    @Published var draft = ""

    var draftIsBlank: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// What the history window's buttons do. The keyboard shortcuts call the same functions.
struct PanelActions {
    var paste: (Clip) -> Void
    var togglePin: (Clip) -> Void
    var delete: (Clip) -> Void
    var edit: (Clip) -> Void
    var pasteSelected: () -> Void
    var pinSelected: () -> Void
    var deleteSelected: () -> Void
    var editSelected: () -> Void
    var saveEdit: () -> Void
    var cancelEdit: () -> Void
    var close: () -> Void
    var clearHistory: () -> Void
    var openSettings: () -> Void
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private let model = PanelModel()
    private let onPaste: (Clip) -> Void
    private let onOpenSettings: () -> Void
    private var panel: ClipPanel!
    private var keyMonitor: Any?
    /// When the panel last closed. A click on the menu bar icon closes the panel
    /// (it loses focus) before the click arrives, so that click shouldn't reopen it.
    private var lastHidden = Date.distantPast

    /// Called with true when the panel opens and false when it closes.
    var onVisibilityChange: ((Bool) -> Void)?

    init(store: ClipStore, onPaste: @escaping (Clip) -> Void, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onPaste = onPaste
        self.onOpenSettings = onOpenSettings
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let size = NSSize(width: 440, height: 480)
        let panel = ClipPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 12)

        let actions = PanelActions(
            paste: { [weak self] clip in self?.paste(clip) },
            togglePin: { [weak self] clip in self?.togglePin(clip) },
            delete: { [weak self] clip in self?.delete(clip) },
            edit: { [weak self] clip in self?.edit(clip) },
            pasteSelected: { [weak self] in self?.withSelected { self?.paste($0) } },
            pinSelected: { [weak self] in self?.withSelected { self?.togglePin($0) } },
            deleteSelected: { [weak self] in self?.withSelected { self?.delete($0) } },
            editSelected: { [weak self] in self?.withSelected { self?.edit($0) } },
            saveEdit: { [weak self] in self?.saveEdit() },
            cancelEdit: { [weak self] in self?.cancelEdit() },
            close: { [weak self] in self?.hide() },
            clearHistory: { [weak self] in self?.clearHistory() },
            openSettings: { [weak self] in
                self?.hide()
                self?.onOpenSettings()
            })
        let list = ClipListView(store: store, model: model, actions: actions)
        let host = NSHostingView(rootView: list)
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        self.panel = panel
    }

    // MARK: Showing and hiding

    /// Opens or closes the history. With an anchor (the menu bar icon's frame) it opens
    /// just below it; otherwise near the mouse.
    func toggle(below anchor: NSRect? = nil) {
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHidden) > 0.3 {
            show(below: anchor)
        }
    }

    func show(below anchor: NSRect? = nil) {
        model.query = ""
        model.selection = 0
        model.confirmingClear = false
        model.editingID = nil
        model.focusToken += 1
        if let anchor {
            position(below: anchor)
        } else {
            positionNearMouse()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        installKeyMonitor()
        onVisibilityChange?(true)
    }

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
        lastHidden = Date()
        onVisibilityChange?(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()  // clicking anywhere else closes it
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        place(at: NSPoint(x: mouse.x, y: mouse.y - 10), on: screen(containing: mouse))
    }

    /// Centers the panel under the menu bar icon.
    private func position(below anchor: NSRect) {
        place(at: NSPoint(x: anchor.midX, y: anchor.minY - 4),
              on: screen(containing: NSPoint(x: anchor.midX, y: anchor.midY)))
    }

    /// Puts the panel's top-center at `point`, kept inside the screen's visible area.
    private func place(at point: NSPoint, on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = KeyPress(event)
            let handled = MainActor.assumeIsolated { self?.handle(key) ?? false }
            return handled ? nil : event
        }
    }

    /// The parts of a key event the panel cares about.
    private struct KeyPress: Sendable {
        let keyCode: Int
        let command: Bool
        let shift: Bool
        let characters: String?
        let windowNumber: Int

        init(_ event: NSEvent) {
            keyCode = Int(event.keyCode)
            command = event.modifierFlags.contains(.command)
            shift = event.modifierFlags.contains(.shift)
            characters = event.charactersIgnoringModifiers
            windowNumber = event.windowNumber
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the key was handled and shouldn't reach the search field.
    private func handle(_ key: KeyPress) -> Bool {
        guard key.windowNumber == panel.windowNumber else { return false }
        if let id = model.editingID {
            if store.clips.contains(where: { $0.id == id }) { return handleWhileEditing(key) }
            model.editingID = nil  // the clip was deleted or trimmed while editing
        }
        let command = key.command
        let items = store.search(model.query)
        let selected = items.indices.contains(model.selection) ? items[model.selection] : nil

        switch key.keyCode {
        case kVK_Escape:
            // First esc cancels the "delete all" confirmation; otherwise it closes the window.
            if model.confirmingClear {
                model.confirmingClear = false
            } else {
                hide()
            }
            return true
        case kVK_UpArrow:
            moveSelection(by: -1, count: items.count)
            return true
        case kVK_DownArrow:
            moveSelection(by: 1, count: items.count)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let selected { paste(selected) }
            return true
        case kVK_Delete where command:
            if let selected { delete(selected) }
            return true
        case kVK_ANSI_P where command:
            if let selected { togglePin(selected) }
            return true
        case kVK_ANSI_E where command:
            if let selected { edit(selected) }
            return true
        default:
            break
        }

        if command, let digit = key.characters.flatMap(Int.init),
           (1...9).contains(digit), digit <= items.count {
            paste(items[digit - 1])
            return true
        }
        return false
    }

    /// In the editor, esc cancels and ⌘↩ saves; every other key goes to the text.
    private func handleWhileEditing(_ key: KeyPress) -> Bool {
        switch key.keyCode {
        case kVK_Escape:
            cancelEdit()
            return true
        case kVK_Return where key.command, kVK_ANSI_KeypadEnter where key.command:
            saveEdit()
            return true
        default:
            break
        }
        // ClipKeep has no Edit menu, so cut, copy, paste, select all and undo
        // wouldn't reach the text editor on their own.
        guard key.command, let action = Self.editingAction(for: key) else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }

    private static func editingAction(for key: KeyPress) -> Selector? {
        switch key.characters?.lowercased() {
        case "x": return #selector(NSText.cut(_:))
        case "c": return #selector(NSText.copy(_:))
        case "v": return #selector(NSText.paste(_:))
        case "a": return #selector(NSText.selectAll(_:))
        case "z": return key.shift ? Selector(("redo:")) : Selector(("undo:"))
        default: return nil
        }
    }

    private func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        model.selection = min(max(model.selection + delta, 0), count - 1)
    }

    // MARK: Actions

    /// Runs `action` on the highlighted clip, if there is one.
    private func withSelected(_ action: (Clip) -> Void) {
        let items = store.search(model.query)
        guard items.indices.contains(model.selection) else { return }
        action(items[model.selection])
    }

    /// Deletes every clip except pinned ones (after the user confirms in the window).
    private func clearHistory() {
        store.clearUnpinned()
        model.confirmingClear = false
        model.selection = 0
    }

    private func paste(_ clip: Clip) {
        hide()
        onPaste(clip)
    }

    private func togglePin(_ clip: Clip) {
        store.togglePin(clip.id)
        // Keep the same clip selected after it moves.
        if let index = store.search(model.query).firstIndex(where: { $0.id == clip.id }) {
            model.selection = index
        }
    }

    private func delete(_ clip: Clip) {
        store.delete(clip.id)
        let count = store.search(model.query).count
        model.selection = max(0, min(model.selection, count - 1))
    }

    /// Opens the in-window editor for a text clip. Images can't be edited.
    private func edit(_ clip: Clip) {
        guard !clip.isImage else { return }
        model.confirmingClear = false
        model.draft = clip.text
        model.editingID = clip.id
    }

    private func saveEdit() {
        guard let id = model.editingID, !model.draftIsBlank else { return }
        store.updateText(id, to: model.draft)
        model.editingID = nil
        // Keep the edited clip selected, in case the new text no longer matches the search.
        if let index = store.search(model.query).firstIndex(where: { $0.id == id }) {
            model.selection = index
        } else {
            model.query = ""
            model.selection = store.search("").firstIndex { $0.id == id } ?? 0
        }
    }

    private func cancelEdit() {
        model.editingID = nil
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
