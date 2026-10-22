import Foundation

/// Clipboard history, newest first, saved as JSON in Application Support.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []

    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipKeep", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    var fileLocation: URL { fileURL }

    /// Adds a clip. Copying the same text again moves the existing clip to the top
    /// instead of storing a duplicate.
    func add(text: String, rtf: Data?, sourceBundleID: String?, sourceName: String?, limit: Int) {
        if let index = clips.firstIndex(where: { $0.text == text }) {
            var clip = clips.remove(at: index)
            clip.date = Date()
            clip.rtf = rtf
            clip.sourceBundleID = sourceBundleID ?? clip.sourceBundleID
            clip.sourceName = sourceName ?? clip.sourceName
            clips.insert(clip, at: 0)
        } else {
            clips.insert(
                Clip(text: text, rtf: rtf, sourceBundleID: sourceBundleID,
                     sourceName: sourceName, date: Date()),
                at: 0)
        }
        trim(to: limit)
        scheduleSave()
    }

    /// Records a paste and moves the clip to the top.
    func markUsed(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips.remove(at: index)
        clip.pasteCount += 1
        clip.date = Date()
        clips.insert(clip, at: 0)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].pinned.toggle()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        clips.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearUnpinned() {
        clips.removeAll { !$0.pinned }
        scheduleSave()
    }

    /// Drops the oldest unpinned clips beyond the limit.
    func trim(to limit: Int) {
        var unpinnedSeen = 0
        let before = clips.count
        clips = clips.filter { clip in
            if clip.pinned { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= limit
        }
        if clips.count != before { scheduleSave() }
    }

    /// Case-insensitive text search. Pinned clips come first.
    func search(_ query: String) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = q.isEmpty ? clips : clips.filter { $0.text.localizedCaseInsensitiveContains(q) }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            clips = try JSONDecoder().decode([Clip].self, from: data)
        } catch {
            NSLog("ClipKeep: could not read history, moving it aside: \(error)")
            try? FileManager.default.moveItem(
                at: fileURL, to: fileURL.appendingPathExtension("unreadable"))
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: fileURL, options: .atomic)
            // Clipboard history can hold private text; keep it readable only by this user.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("ClipKeep: could not save history: \(error)")
        }
    }
}
