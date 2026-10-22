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
    private var recordingItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(store: store, settings: settings)
        monitor.start()

        panel = PanelController(store: store) { [weak self] clip in self?.paste(clip) }

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        if hotKey == nil {
            NSLog("ClipKeep: ⇧⌘V is already used by another app; open history from the menu bar instead.")
        }

        setupStatusItem()

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
        Paster.write(clip, plainText: settings.pastePlainText)
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
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipKeep")

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
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit ClipKeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        recordingItem.title = settings.recording ? "Pause Recording" : "Resume Recording"
    }

    @objc private func openHistory() {
        // Wait for the menu to close first, or it steals the panel's focus.
        DispatchQueue.main.async { self.panel.show() }
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

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, window: SettingsWindowModel())
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
