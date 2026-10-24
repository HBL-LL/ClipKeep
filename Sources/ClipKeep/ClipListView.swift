import AppKit
import SwiftUI

struct ClipListView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    @FocusState private var searchFocused: Bool
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let clip = model.editingID.flatMap({ id in store.clips.first { $0.id == id } }) {
                editor(for: clip)
            } else {
                history
            }
        }
        .frame(width: 440, height: 480)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    @ViewBuilder
    private var history: some View {
        let items = store.search(model.query)
        let selected = items.indices.contains(model.selection) ? items[model.selection] : nil

        header(canClear: store.clips.contains { !$0.pinned })
            .onAppear { searchFocused = true }  // also when coming back from the editor

        if model.confirmingClear {
            confirmClearBar
        }

        Divider()

        if items.isEmpty {
            emptyState
        } else {
            list(items)
        }

        Divider()
        footer(count: items.count, selected: selected)
    }

    // MARK: Header

    private func header(canClear: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            IconButton(symbol: "trash", help: "Clear history") {
                model.confirmingClear = true
            }
            .disabled(!canClear)
            IconButton(symbol: "gearshape", help: "Settings", action: actions.openSettings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var confirmClearBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Delete all clips?").font(.system(size: 12, weight: .semibold))
                Text("Pinned clips are kept.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { model.confirmingClear = false }
                .controlSize(.small)
            // Drawn by hand so it stays red: the panel never makes ClipKeep the active app,
            // and standard prominent buttons turn grey in inactive apps.
            Button(role: .destructive, action: actions.clearHistory) {
                Text("Delete All")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.10))
    }

    // MARK: List

    private func list(_ items: [Clip]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(
                            clip: clip, index: index, selected: index == model.selection,
                            thumbnail: clip.image.flatMap { Thumbnails.thumbnail(for: store.imageURL(for: $0)) })
                            .id(clip.id)
                            .onTapGesture { actions.paste(clip) }
                            .onHover { inside in if inside { model.selection = index } }
                            .contextMenu {
                                Button("Paste") { actions.paste(clip) }
                                Button(clip.pinned ? "Unpin" : "Pin") { actions.togglePin(clip) }
                                if !clip.isImage {
                                    Button("Edit…") { actions.edit(clip) }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { actions.delete(clip) }
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

    // MARK: Editor

    private func editor(for clip: Clip) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Edit clip").font(.system(size: 13, weight: .semibold))
                    if clip.rtf != nil {
                        Text("Saving removes its formatting.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            TextEditor(text: $model.draft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(10)

            Divider()

            HStack(spacing: 6) {
                ShortcutButton(keys: "⌘↩", label: "Save", action: actions.saveEdit)
                    .disabled(model.draftIsBlank)
                ShortcutButton(keys: "esc", label: "Cancel", action: actions.cancelEdit)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .onAppear { editorFocused = true }
    }

    // MARK: Footer

    /// Each hint is also a button that does the same thing as its key.
    private func footer(count: Int, selected: Clip?) -> some View {
        HStack(spacing: 6) {
            ShortcutButton(keys: "↩", label: "Paste", action: actions.pasteSelected)
                .disabled(selected == nil)
            ShortcutButton(keys: "⌘P", label: "Pin", action: actions.pinSelected)
                .disabled(selected == nil)
            ShortcutButton(keys: "⌘E", label: "Edit", action: actions.editSelected)
                .disabled(selected == nil || selected?.isImage == true)
            ShortcutButton(keys: "⌘⌫", label: "Delete", action: actions.deleteSelected)
                .disabled(selected == nil)
            ShortcutButton(keys: "esc", label: "Close", action: actions.close)
            Spacer()
            Text("\(count) \(count == 1 ? "clip" : "clips")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

/// A small borderless icon button for the header.
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .pointingHandCursor()
    }
}

/// A footer hint drawn as a keycap plus label, clickable like the key it shows.
private struct ShortcutButton: View {
    let keys: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(keys)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 0.5))
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShortcutButtonStyle())
        .help("\(label) (\(keys))")
        .pointingHandCursor()
    }
}

/// Plain look with a soft highlight while pressed and a faded look when disabled.
private struct ShortcutButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.05)))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

private extension View {
    /// Shows the pointing-hand cursor while hovering, like a link.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let index: Int
    let selected: Bool
    let thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if clip.pinned {
                        Image(systemName: "pin.fill")
                    }
                    if let image = clip.image {
                        Text("\(image.width) × \(image.height)")
                        Text("·")
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
    private var content: some View {
        if clip.isImage {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 72, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            } else {
                Label("Image unavailable", systemImage: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(clip.preview)
                .font(.system(size: 13))
                .lineLimit(2)
        }
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
