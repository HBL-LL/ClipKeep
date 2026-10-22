import Foundation

/// One saved clipboard entry: text (with optional rich text) or an image.
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Empty for image clips.
    var text: String
    /// Rich-text version, kept so "paste with formatting" works.
    var rtf: Data?
    /// Set for image clips; the pixels live in a separate PNG file.
    var image: ClipImage?
    var sourceBundleID: String?
    var sourceName: String?
    var date: Date
    var pinned = false
    var pasteCount = 0

    var isImage: Bool { image != nil }

    /// Single-line text for the list, cut short so huge clips stay cheap to draw.
    var preview: String {
        if let image { return "Image  \(image.width) × \(image.height)" }
        return String(text.prefix(400))
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    /// What search matches against. Images can be found by typing "image".
    var searchText: String { isImage ? preview : text }
}

struct ClipImage: Codable, Equatable {
    /// File name inside the store's images folder.
    var fileName: String
    var width: Int
    var height: Int
    var byteCount: Int
    /// SHA-256 of the decoded pixels, used to spot the same image copied twice.
    var sha256: String
}
