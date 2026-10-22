import Foundation
import Combine

struct ExcludedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// User preferences, backed by UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let historyLimit = "historyLimit"
        static let recording = "recording"
        static let pasteDirectly = "pasteDirectly"
        static let pastePlainText = "pastePlainText"
        static let ignoreConcealed = "ignoreConcealed"
        static let saveImages = "saveImages"
        static let excludedApps = "excludedApps"
    }

    static let defaultExcludedApps = [
        ExcludedApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        ExcludedApp(bundleID: "com.apple.Passwords", name: "Passwords"),
    ]

    /// How many unpinned clips to keep. Pinned clips don't count.
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: Key.historyLimit) } }
    @Published var recording: Bool { didSet { defaults.set(recording, forKey: Key.recording) } }
    /// Press ⌘V for the user after a clip is chosen.
    @Published var pasteDirectly: Bool { didSet { defaults.set(pasteDirectly, forKey: Key.pasteDirectly) } }
    @Published var pastePlainText: Bool { didSet { defaults.set(pastePlainText, forKey: Key.pastePlainText) } }
    /// Skip clipboard content that password managers mark as hidden.
    @Published var ignoreConcealed: Bool { didSet { defaults.set(ignoreConcealed, forKey: Key.ignoreConcealed) } }
    /// Record copied images (screenshots, pictures) as well as text.
    @Published var saveImages: Bool { didSet { defaults.set(saveImages, forKey: Key.saveImages) } }
    @Published var excludedApps: [ExcludedApp] {
        didSet {
            if let data = try? JSONEncoder().encode(excludedApps) {
                defaults.set(data, forKey: Key.excludedApps)
            }
        }
    }

    private init() {
        defaults.register(defaults: [
            Key.historyLimit: 200,
            Key.recording: true,
            Key.pasteDirectly: true,
            Key.pastePlainText: false,
            Key.ignoreConcealed: true,
            Key.saveImages: true,
        ])
        historyLimit = defaults.integer(forKey: Key.historyLimit)
        recording = defaults.bool(forKey: Key.recording)
        pasteDirectly = defaults.bool(forKey: Key.pasteDirectly)
        pastePlainText = defaults.bool(forKey: Key.pastePlainText)
        ignoreConcealed = defaults.bool(forKey: Key.ignoreConcealed)
        saveImages = defaults.bool(forKey: Key.saveImages)
        if let data = defaults.data(forKey: Key.excludedApps),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedApps = apps
        } else {
            excludedApps = Settings.defaultExcludedApps
        }
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excludedApps.contains { $0.bundleID == bundleID }
    }
}
