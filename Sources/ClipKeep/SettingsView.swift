import AppKit
import ServiceManagement
import SwiftUI

/// Window state for the settings tabs. Kept in an object rather than @State because the
/// @State macro isn't available without full Xcode.
@MainActor
final class SettingsWindowModel: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var hasAccessibility = Paster.hasAccessibility

    private var accessibilityObserver: NSObjectProtocol?
    private var accessibilityPoll: Timer?

    init() {
        // macOS posts this when any app's Accessibility switch changes; the permission
        // itself is updated a moment later, so check again shortly after.
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.refreshAccessibility() }
            }
        }
        pollAccessibilityUntilAllowed()
    }

    /// Re-reads whether ClipKeep may press ⌘V for the user.
    func refreshAccessibility() {
        hasAccessibility = Paster.hasAccessibility
        pollAccessibilityUntilAllowed()
    }

    /// While access is missing, check every couple of seconds so the status flips to
    /// "Allowed" as soon as the user turns it on, without reopening anything.
    private func pollAccessibilityUntilAllowed() {
        if hasAccessibility {
            accessibilityPoll?.invalidate()
            accessibilityPoll = nil
            return
        }
        guard accessibilityPoll == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPoll = timer
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}

/// The Settings window: a Mac-style toolbar of tabs (General, Pasting, Privacy, Updates).
@MainActor
enum SettingsWindow {
    static func make(settings: Settings, updater: Updater, onClearHistory: @escaping () -> Void) -> NSWindow {
        let model = SettingsWindowModel()
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        func add<Content: View>(_ title: String, _ symbol: String, _ view: Content) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            host.title = title  // shown as the window title when this tab is selected
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape",
            GeneralSettingsView(settings: settings, window: model, onClearHistory: onClearHistory))
        add("Pasting", "doc.on.clipboard", PastingSettingsView(settings: settings, window: model))
        add("Privacy", "hand.raised", PrivacySettingsView(settings: settings))
        add("Updates", "arrow.triangle.2.circlepath", UpdatesSettingsView(settings: settings, updater: updater))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        return window
    }
}

private let settingsWidth: CGFloat = 460

// MARK: General

struct GeneralSettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var window: SettingsWindowModel
    let onClearHistory: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { window.launchAtLogin },
                    set: { window.launchAtLogin = $0; window.setLaunchAtLogin($0) }))
                if let loginError = window.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Open clipboard history") {
                    Text("⇧⌘V").foregroundStyle(.secondary)
                }
            }

            Section {
                Stepper("Keep the last \(settings.historyLimit) clips",
                        value: $settings.historyLimit, in: 10...2000, step: 10)
                Toggle("Save copied images", isOn: $settings.saveImages)
                LabeledContent {
                    Button("Clear History…", action: onClearHistory)
                } label: {
                    Text("Delete saved clips")
                    Text("Pinned clips are kept.")
                }
            } header: {
                Text("History")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit ClipKeep") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 350)
    }
}

// MARK: Pasting

struct PastingSettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var window: SettingsWindowModel

    var body: some View {
        Form {
            Section {
                Toggle("Paste into the front app automatically", isOn: $settings.pasteDirectly)
                Toggle("Paste as plain text", isOn: $settings.pastePlainText)
            } footer: {
                Text("When automatic pasting is off, choosing a clip copies it and you press ⌘V yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if window.hasAccessibility {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    LabeledContent {
                        Button("Grant Access…") { Paster.requestAccessibility() }
                    } label: {
                        Text("Not allowed yet")
                        Text("ClipKeep needs this to press ⌘V for you.")
                    }
                    LabeledContent {
                        Button("Open Settings") { Paster.openAccessibilitySettings() }
                    } label: {
                        Text("Already switched on?")
                        Text("After an update, macOS can keep ClipKeep's old entry. In Accessibility, select ClipKeep, click −, then click Grant Access again.")
                    }
                }
            } header: {
                Text("Accessibility")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 340)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            window.refreshAccessibility()
        }
    }
}

// MARK: Privacy

struct PrivacySettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("Skip passwords and other hidden content", isOn: $settings.ignoreConcealed)
            } footer: {
                Text("Password managers mark what they copy as hidden; ClipKeep won't save it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.excludedApps) { app in
                    HStack {
                        if let icon = AppIcons.icon(for: app.bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(app.name)
                        Spacer()
                        Button {
                            settings.excludedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop ignoring \(app.name)")
                    }
                }
                Menu("Add App…") {
                    ForEach(addableApps, id: \.bundleID) { app in
                        Button(app.name) { settings.excludedApps.append(app) }
                    }
                }
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Nothing you copy in these apps is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 340)
    }

    /// Running apps with a window that aren't already ignored.
    private var addableApps: [ExcludedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ExcludedApp? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !settings.isExcluded(id) else { return nil }
                return ExcludedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: Updates

struct UpdatesSettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: updater.currentVersion)
                Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                LabeledContent {
                    HStack(spacing: 8) {
                        if updater.isBusy {
                            ProgressView().controlSize(.small)
                        }
                        Button("Check for Updates") {
                            Task { await updater.check(announceResult: false) }
                        }
                        .disabled(updater.isBusy)
                    }
                } label: {
                    Text(updater.statusText)
                }
            }

            Section {
                Link("Release notes on GitHub",
                     destination: URL(string: "https://github.com/\(Updater.repository)/releases")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 200)
    }
}
