import Foundation

/// One saved clipboard entry.
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    /// Rich-text version, kept so "paste with formatting" works.
    var rtf: Data?
    var sourceBundleID: String?
    var sourceName: String?
    var date: Date
    var pinned = false
    var pasteCount = 0

    /// Single-line text for the list, cut short so huge clips stay cheap to draw.
    var preview: String {
        String(text.prefix(400))
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }
}
