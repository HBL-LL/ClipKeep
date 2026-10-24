import Foundation

/// Clipboard history, newest first, saved as JSON in Application Support.
/// Image pixels are kept as PNG files in an `images` folder next to it.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []

    private let fileURL: URL
    private let imagesURL: URL
    private var pendingSave: DispatchWorkItem?

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipKeep", isDirectory: true)
        fileURL = dir.appendingPathComponent("history.json")
        imagesURL = dir.appendingPathComponent("images", isDirectory: true)
        for folder in [dir, imagesURL] {
            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        load()
        removeUnusedImageFiles()
    }

    func imageURL(for image: ClipImage) -> URL {
        imagesURL.appendingPathComponent(image.fileName)
    }

    // MARK: Adding

    /// Adds a text clip. Copying the same text again moves the existing clip to the top
    /// instead of storing a duplicate.
    func add(text: String, rtf: Data?, sourceBundleID: String?, sourceName: String?, limit: Int) {
        if let index = clips.firstIndex(where: { !$0.isImage && $0.text == text }) {
            moveToTop(index, sourceBundleID: sourceBundleID, sourceName: sourceName) { $0.rtf = rtf }
        } else {
            clips.insert(
                Clip(text: text, rtf: rtf, sourceBundleID: sourceBundleID,
                     sourceName: sourceName, date: Date()),
                at: 0)
        }
        trim(to: limit)
        scheduleSave()
    }

    /// Adds an image clip, writing its PNG file. The same image copied again moves to the top.
    func add(image encoded: EncodedImage, sourceBundleID: String?, sourceName: String?, limit: Int) {
        if let index = clips.firstIndex(where: { $0.image?.sha256 == encoded.sha256 }) {
            moveToTop(index, sourceBundleID: sourceBundleID, sourceName: sourceName) { _ in }
        } else {
            let id = UUID()
            let image = ClipImage(
                fileName: "\(id.uuidString).png", width: encoded.width, height: encoded.height,
                byteCount: encoded.png.count, sha256: encoded.sha256)
            do {
                let url = imageURL(for: image)
                try encoded.png.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                NSLog("ClipKeep: could not save image: \(error)")
                return
            }
            clips.insert(
                Clip(id: id, text: "", image: image, sourceBundleID: sourceBundleID,
                     sourceName: sourceName, date: Date()),
                at: 0)
        }
        trim(to: limit)
        scheduleSave()
    }

    private func moveToTop(_ index: Int, sourceBundleID: String?, sourceName: String?,
                           update: (inout Clip) -> Void) {
        var clip = clips.remove(at: index)
        clip.date = Date()
        clip.sourceBundleID = sourceBundleID ?? clip.sourceBundleID
        clip.sourceName = sourceName ?? clip.sourceName
        update(&clip)
        clips.insert(clip, at: 0)
    }

    // MARK: Changing

    /// Records a paste and moves the clip to the top.
    func markUsed(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips.remove(at: index)
        clip.pasteCount += 1
        clip.date = Date()
        clips.insert(clip, at: 0)
        scheduleSave()
    }

    /// Replaces a text clip's text. Its rich text is dropped, since it no longer matches.
    func updateText(_ id: UUID, to text: String) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              !clips[index].isImage, clips[index].text != text else { return }
        clips[index].text = text
        clips[index].rtf = nil
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].pinned.toggle()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        remove { $0.id == id }
    }

    func clearUnpinned() {
        remove { !$0.pinned }
    }

    /// Drops the oldest unpinned clips beyond the limit.
    func trim(to limit: Int) {
        var unpinnedSeen = 0
        let keep = Set(clips.compactMap { clip -> UUID? in
            if clip.pinned { return clip.id }
            unpinnedSeen += 1
            return unpinnedSeen <= limit ? clip.id : nil
        })
        remove { !keep.contains($0.id) }
    }

    /// Removes matching clips and deletes their image files.
    private func remove(where shouldRemove: (Clip) -> Bool) {
        let removed = clips.filter(shouldRemove)
        guard !removed.isEmpty else { return }
        clips.removeAll(where: shouldRemove)
        for image in removed.compactMap(\.image) {
            try? FileManager.default.removeItem(at: imageURL(for: image))
            Thumbnails.forget(image.fileName)
        }
        scheduleSave()
    }

    /// Case-insensitive search. Pinned clips come first.
    func search(_ query: String) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = q.isEmpty ? clips : clips.filter { $0.searchText.localizedCaseInsensitiveContains(q) }
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
        // Drop image clips whose file has gone missing.
        clips.removeAll { clip in
            guard let image = clip.image else { return false }
            return !FileManager.default.fileExists(atPath: imageURL(for: image).path)
        }
    }

    /// Deletes image files that no clip refers to (e.g. left over from a crash).
    private func removeUnusedImageFiles() {
        let used = Set(clips.compactMap(\.image?.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path)) ?? []
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(file))
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
