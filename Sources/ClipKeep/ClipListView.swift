import AppKit
import SwiftUI

struct ClipListView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: PanelModel
    let onPaste: (Clip) -> Void
    let onTogglePin: (Clip) -> Void
    let onDelete: (Clip) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = store.search(model.query)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if items.isEmpty {
                emptyState
            } else {
                list(items)
            }

            Divider()
            footer(count: items.count)
        }
        .frame(width: 440, height: 480)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    private func list(_ items: [Clip]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(clip: clip, index: index, selected: index == model.selection)
                            .id(clip.id)
                            .onTapGesture { onPaste(clip) }
                            .onHover { inside in if inside { model.selection = index } }
                            .contextMenu {
                                Button("Paste") { onPaste(clip) }
                                Button(clip.pinned ? "Unpin" : "Pin") { onTogglePin(clip) }
                                Divider()
                                Button("Delete", role: .destructive) { onDelete(clip) }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) {
                if items.indices.contains(model.selection) {
                    proxy.scrollTo(items[model.selection].id)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Copy something and it will show up here." : "No clips match “\(model.query)”.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 12) {
            Text("↩ Paste")
            Text("⌘P Pin")
            Text("⌘⌫ Delete")
            Text("esc Close")
            Spacer()
            Text("\(count) \(count == 1 ? "clip" : "clips")")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct ClipRow: View {
    let clip: Clip
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.preview)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if clip.pinned {
                        Image(systemName: "pin.fill")
                    }
                    Text(clip.sourceName ?? "Unknown app")
                    Text("·")
                    Text(clip.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AppIcons.icon(for: clip.sourceBundleID) {
            Image(nsImage: image).resizable()
        } else {
            Image(systemName: "doc.on.clipboard")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(2)
        }
    }
}

/// Caches app icons by bundle ID so scrolling stays smooth.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}
