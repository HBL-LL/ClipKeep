import AppKit
import ServiceManagement
import SwiftUI

/// Window state for SettingsView. Kept in an object rather than @State because the
/// @State macro isn't available without full Xcode.
@MainActor
final class SettingsWindowModel: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var hasAccessibility = Paster.hasAccessibility

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

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var window: SettingsWindowModel
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { window.launchAtLogin },
                    set: { window.launchAtLogin = $0; window.setLaunchAtLogin($0) }))
                if let loginError = window.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Stepper("Keep the last \(settings.historyLimit) clips",
                        value: $settings.historyLimit, in: 10...2000, step: 10)
                Toggle("Save copied images", isOn: $settings.saveImages)
                LabeledContent("Open history", value: "⇧⌘V")
            }

            Section {
                Toggle("Paste into the front app automatically", isOn: $settings.pasteDirectly)
                Toggle("Paste as plain text", isOn: $settings.pastePlainText)
                if settings.pasteDirectly && !window.hasAccessibility {
                    HStack {
                        Text("Needs Accessibility access to press ⌘V for you.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") { Paster.requestAccessibility() }
                    }
                }
            } header: {
                Text("Pasting")
            }

            Section {
                Toggle("Skip passwords and other hidden content", isOn: $settings.ignoreConcealed)
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
                Menu("Ignore an App…") {
                    ForEach(addableApps, id: \.bundleID) { app in
                        Button(app.name) { settings.excludedApps.append(app) }
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Nothing you copy in ignored apps is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                LabeledContent("Version", value: updater.currentVersion)
                Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                HStack {
                    Text(updater.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updater.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check for Updates") {
                        Task { await updater.check(announceResult: false) }
                    }
                    .disabled(updater.isBusy)
                }
            }

            Section {
                HStack {
                    Text("Right-click the menu bar icon to pause recording or clear history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit ClipKeep") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 700)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            window.hasAccessibility = Paster.hasAccessibility
        }
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
