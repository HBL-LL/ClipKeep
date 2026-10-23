import AppKit

/// Checks GitHub for new ClipKeep releases and installs them on request.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repository = "HBL-LL/ClipKeep"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private let lastCheckedKey = "lastUpdateCheck"
    private var settings: Settings?
    private var timer: Timer?

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: lastCheckedKey) as? Date
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isBusy: Bool { status == .checking || status == .installing }

    var statusText: String {
        switch status {
        case .idle:
            guard let lastChecked else { return "Not checked yet." }
            return "Last checked \(lastChecked.formatted(.relative(presentation: .named)))."
        case .checking: return "Checking…"
        case .upToDate: return "You're up to date."
        case .available(let version): return "Version \(version) is available."
        case .installing: return "Downloading and installing…"
        case .failed(let message): return message
        }
    }

    // MARK: Automatic checks

    /// Checks once a day (if enabled), starting shortly after launch.
    func startAutomaticChecks(settings: Settings) {
        self.settings = settings
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard settings?.autoCheckUpdates == true, !isBusy else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 24 * 60 * 60 { return }
        Task { await check(announceResult: false) }
    }

    // MARK: Checking and installing

    /// Looks for a newer release and offers to install it.
    /// `announceResult` also shows "up to date" and errors in an alert (used from the menu).
    func check(announceResult: Bool) async {
        guard !isBusy else { return }
        status = .checking
        do {
            let release = try await ReleaseFetcher.latest(repository: Self.repository)
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: lastCheckedKey)
            if Version.isNewer(release.version, than: currentVersion) {
                status = .available(release.version)
                offer(release)
            } else {
                status = .upToDate
                if announceResult {
                    showAlert("You're up to date", "ClipKeep \(currentVersion) is the newest version.")
                }
            }
        } catch {
            status = .failed("Couldn't check for updates: \(error.localizedDescription)")
            if announceResult {
                showAlert("Couldn't check for updates", error.localizedDescription)
            }
        }
    }

    private func offer(_ release: ReleaseInfo) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "ClipKeep \(release.version) is available"
        var details = "You have version \(currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            details += "\n\n" + String(notes.prefix(800))
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await install(release) }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private func install(_ release: ReleaseInfo) async {
        status = .installing
        let appURL = Bundle.main.bundleURL
        do {
            try await UpdateInstaller.install(
                release, replacing: appURL,
                bundleID: Bundle.main.bundleIdentifier ?? "local.clipkeep")
            relaunch(at: appURL)
        } catch {
            status = .failed("Update failed: \(error.localizedDescription)")
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Couldn't install the update"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Download Manually")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    /// Quits, then reopens the app once this process has exited.
    private func relaunch(at appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
            appURL.path,
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
