import CryptoKit
import Foundation

// Update logic with no UI: find the latest GitHub release, compare versions,
// and download, check, and swap in a new ClipKeep.app.

struct ReleaseInfo: Sendable, Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL
    /// SHA-256 of the zip as reported by GitHub, if available.
    let sha256: String?
}

enum UpdateError: LocalizedError {
    case noReleases
    case badResponse(Int)
    case noDownload
    case checksumMismatch
    case extractFailed
    case invalidApp(String)
    case signatureInvalid
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .noReleases: return "No releases have been published yet."
        case .badResponse(let code): return "GitHub answered with HTTP \(code)."
        case .noDownload: return "The latest release has no ClipKeep.zip to download."
        case .checksumMismatch: return "The download doesn't match its checksum, so it wasn't installed."
        case .extractFailed: return "The download couldn't be unzipped."
        case .invalidApp(let reason): return "The downloaded app isn't valid: \(reason)."
        case .signatureInvalid: return "The downloaded app's code signature is broken, so it wasn't installed."
        case .notWritable(let path): return "ClipKeep can't replace itself in \(path). Move it to your Applications folder and try again."
        }
    }
}

enum Version {
    /// True if `candidate` is a higher version than `current` (e.g. "1.10.0" > "1.9.2").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

enum ReleaseFetcher {
    static let assetName = "ClipKeep.zip"

    static func latest(repository: String) async throws -> ReleaseInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipKeep-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError.noReleases }
        guard status == 200 else { throw UpdateError.badResponse(status) }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == assetName }) else {
            throw UpdateError.noDownload
        }
        let sha256 = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return ReleaseInfo(
            version: release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")),
            notes: release.body ?? "",
            pageURL: release.html_url,
            downloadURL: asset.browser_download_url,
            sha256: sha256)
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
    }
}

enum UpdateInstaller {
    /// Downloads the release, checks it, and replaces the app at `appURL`.
    /// If anything fails, the current app is left (or put back) in place.
    static func install(_ release: ReleaseInfo, replacing appURL: URL, bundleID: String) async throws {
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipKeepUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(ReleaseFetcher.assetName)
        try FileManager.default.moveItem(at: downloaded, to: zip)

        if let expected = release.sha256 {
            let actual = SHA256.hash(data: try Data(contentsOf: zip))
                .map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { throw UpdateError.checksumMismatch }
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else {
            throw UpdateError.extractFailed
        }
        let newApp = unpacked.appendingPathComponent("ClipKeep.app")
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleID else {
            throw UpdateError.invalidApp("it isn't ClipKeep")
        }
        let newVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard newVersion == release.version else {
            throw UpdateError.invalidApp("it is version \(newVersion), expected \(release.version)")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0 else {
            throw UpdateError.signatureInvalid
        }

        // Swap: move the current app aside, move the new one in, and roll back on failure.
        let previous = work.appendingPathComponent("Previous.app")
        try FileManager.default.moveItem(at: appURL, to: previous)
        do {
            try FileManager.default.moveItem(at: newApp, to: appURL)
        } catch {
            try? FileManager.default.moveItem(at: previous, to: appURL)
            throw error
        }
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
