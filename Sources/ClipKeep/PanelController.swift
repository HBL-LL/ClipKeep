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
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private let model = PanelModel()
    private let onPaste: (Clip) -> Void
    private var panel: ClipPanel!
    private var keyMonitor: Any?

    init(store: ClipStore, onPaste: @escaping (Clip) -> Void) {
        self.store = store
        self.onPaste = onPaste
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

        let list = ClipListView(
            store: store, model: model,
            onPaste: { [weak self] clip in self?.paste(clip) },
            onTogglePin: { [weak self] clip in self?.togglePin(clip) },
            onDelete: { [weak self] clip in self?.delete(clip) })
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

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        model.query = ""
        model.selection = 0
        model.focusToken += 1
        positionNearMouse()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()  // clicking anywhere else closes it
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 10)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
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
        let characters: String?
        let windowNumber: Int

        init(_ event: NSEvent) {
            keyCode = Int(event.keyCode)
            command = event.modifierFlags.contains(.command)
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
        let command = key.command
        let items = store.search(model.query)
        let selected = items.indices.contains(model.selection) ? items[model.selection] : nil

        switch key.keyCode {
        case kVK_Escape:
            hide()
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

    private func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        model.selection = min(max(model.selection + delta, 0), count - 1)
    }

    // MARK: Actions

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
