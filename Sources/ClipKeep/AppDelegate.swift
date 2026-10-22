import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let store = ClipStore()
    private var monitor: ClipboardMonitor!
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var recordingItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(store: store, settings: settings)
        monitor.start()

        panel = PanelController(
            store: store,
            onPaste: { [weak self] clip in self?.paste(clip) },
            onOpenSettings: { [weak self] in self?.openSettings() })

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        if hotKey == nil {
            NSLog("ClipKeep: ⇧⌘V is already used by another app; open history from the menu bar instead.")
        }

        setupStatusItem()
        // Keep the menu bar icon highlighted while the history is open from it.
        panel.onVisibilityChange = { [weak self] visible in
            self?.statusItem.button?.highlight(visible)
        }

        Updater.shared.startAutomaticChecks(settings: settings)

        settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in self?.store.trim(to: limit) }
            .store(in: &cancellables)
        settings.$recording
            .sink { [weak self] on in self?.statusItem.button?.appearsDisabled = !on }
            .store(in: &cancellables)
    }

    /// Opening ClipKeep again (e.g. double-clicking it) shows the history.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: Pasting

    private func paste(_ clip: Clip) {
        let imageURL = clip.image.map(store.imageURL(for:))
        guard Paster.write(clip, plainText: settings.pastePlainText, imageURL: imageURL) else {
            NSSound.beep()
            return
        }
        monitor.skipCurrentContents()
        store.markUsed(clip.id)

        guard settings.pasteDirectly else { return }
        guard Paster.hasAccessibility else {
            // The clip is on the clipboard; the user can press ⌘V themselves.
            Paster.requestAccessibility()
            return
        }
        // Give the panel a moment to close so ⌘V reaches the app underneath.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Paster.sendCommandV()
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()

        let menu = NSMenu()
        menu.delegate = self

        let open = menu.addItem(withTitle: "Open Clipboard History", action: #selector(openHistory), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(.separator())
        recordingItem = menu.addItem(withTitle: "Pause Recording", action: #selector(toggleRecording), keyEquivalent: "")
        recordingItem.target = self
        menu.addItem(withTitle: "Clear History…", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit ClipKeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu = menu

        // Left click opens the history; right click (or Control-click) shows the menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "ClipKeep: click for history, right-click for options"
    }

    /// The ClipKeep symbol as a template image, so macOS tints it for light and dark
    /// menu bars. Falls back to a system symbol when running outside the app bundle.
    private static func menuBarIcon() -> NSImage? {
        if let image = Bundle.main.image(forResource: "menubarTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "ClipKeep"
            return image
        }
        return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipKeep")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.hide()
            // Attach the menu only for this click so a left click stays free for the history.
            statusItem.menu = statusMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            let anchor = sender.window?.convertToScreen(sender.convert(sender.bounds, to: nil))
            panel.toggle(below: anchor)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        recordingItem.title = settings.recording ? "Pause Recording" : "Resume Recording"
    }

    @objc private func openHistory() {
        // Wait for the menu to close first, or it steals the panel's focus.
        DispatchQueue.main.async { self.panel.show() }
    }

    @objc private func checkForUpdates() {
        Task { await Updater.shared.check(announceResult: true) }
    }

    @objc private func toggleRecording() {
        settings.recording.toggle()
    }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All clips except pinned ones will be deleted."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, window: SettingsWindowModel(), updater: Updater.shared)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "ClipKeep Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
