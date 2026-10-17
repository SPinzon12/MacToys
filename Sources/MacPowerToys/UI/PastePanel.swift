import AppKit
import SwiftUI

// MARK: - UI-side metadata
//
// Everything here is presentation. The tested transform logic
// (`Transforms/PasteTransform.swift`) stays untouched: icons are UI concerns,
// so they live in this file as an extension.

extension PasteTransform {
    var symbolName: String {
        switch self {
        case .plainText: "text.alignleft"
        case .imageToText: "text.viewfinder"
        case .txtFile: "doc.plaintext"
        case .pngFile: "photo"
        case .htmlFile: "chevron.left.forwardslash.chevron.right"
        case .structuredToJSON: "curlybraces"
        case .htmlToMarkdown: "doc.richtext"
        case .videoToMP4: "film"
        case .audioToM4A: "waveform"
        }
    }
}

extension ClipboardEntry {
    /// One-line label for the history list.
    var title: String {
        switch kind {
        case .text:
            let collapsed = (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
        case .image:
            guard let size = imageSize else { return "Image" }
            return "Image \(Int(size.width)) × \(Int(size.height))"
        case .files:
            let first = fileURLs.first?.lastPathComponent ?? "File"
            return fileURLs.count > 1 ? "\(first) +\(fileURLs.count - 1)" : first
        }
    }

    var detail: String {
        switch kind {
        case .text:
            let text = self.text ?? ""
            let words = text.split(whereSeparator: \.isWhitespace).count
            return "\(text.count) characters · \(words) words"
        case .image:
            guard let size = imageSize else { return "Image" }
            return "\(Int(size.width)) × \(Int(size.height)) pixels"
        case .files:
            return fileURLs.count == 1 ? "1 file" : "\(fileURLs.count) files"
        }
    }
}

/// What the user chose in the panel.
enum PastePanelPick {
    case entry(ClipboardEntry)
    case transform(ClipboardEntry, PasteTransform)
}

// MARK: - Model
//
// ponytail: no `@State`/`@Observable` — this CommandLineTools-only toolchain
// ships no SwiftUIMacros plugin, so SwiftUI macros do not compile. Mutable UI
// state lives in an `ObservableObject` instead, which is plain Swift. It is
// deliberately not actor-isolated: every touch happens on the main thread.

final class PastePanelModel: ObservableObject {
    private let history: ClipboardHistory
    private let contentFor: (ClipboardEntry) -> ClipboardContent
    private let imageData: (ClipboardEntry) -> Data?
    private let onPick: (PastePanelPick) -> Void

    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var visible: [ClipboardEntry] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var transforms: [PasteTransform] = []
    @Published var hoveredID: UUID?
    @Published var appeared = false

    private var thumbnails: [UUID: NSImage] = [:]
    private var appIcons: [String: NSImage] = [:]

    var totalCount: Int { history.entries.count }

    var selected: ClipboardEntry? {
        visible.first { $0.id == selectedID }
    }

    init(
        history: ClipboardHistory,
        contentFor: @escaping (ClipboardEntry) -> ClipboardContent,
        imageData: @escaping (ClipboardEntry) -> Data?,
        onPick: @escaping (PastePanelPick) -> Void
    ) {
        self.history = history
        self.contentFor = contentFor
        self.imageData = imageData
        self.onPick = onPick
        refilter()
    }

    // MARK: Selection

    func select(_ id: UUID?) {
        guard id != selectedID else { return }
        selectedID = id
        transforms = selected.map { PasteTransform.available(for: contentFor($0)) } ?? []
    }

    func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visible.count - 1)
        select(visible[next].id)
    }

    func activate() {
        guard let selected else { return }
        onPick(.entry(selected))
    }

    func pick(_ entry: ClipboardEntry) {
        onPick(.entry(entry))
    }

    /// ⌘1…⌘9 and clicks on the "Paste as" list.
    func pickTransform(at index: Int) {
        guard let selected, transforms.indices.contains(index) else { return }
        onPick(.transform(selected, transforms[index]))
    }

    private func refilter() {
        visible = history.filtered(query)
        // Keep the selection while it still matches; otherwise the top hit.
        if let selectedID, visible.contains(where: { $0.id == selectedID }) { return }
        selectedID = nil
        select(visible.first?.id)
    }

    // MARK: Images

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        if let cached = thumbnails[entry.id] { return cached }
        guard let data = imageData(entry), let image = NSImage(data: data) else { return nil }
        thumbnails[entry.id] = image
        return image
    }

    func appIcon(for entry: ClipboardEntry) -> NSImage? {
        guard let bundleID = entry.sourceBundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    struct EntrySection: Identifiable {
        let section: ClipboardHistory.Section
        let entries: [ClipboardEntry]
        var id: String { section.rawValue }
    }

    /// Visible entries grouped into Today / Yesterday / Earlier, order kept.
    var sections: [EntrySection] {
        let now = Date()
        let grouped = Dictionary(grouping: visible) { ClipboardHistory.section(for: $0.date, now: now) }
        return ClipboardHistory.Section.allCases.compactMap { section in
            grouped[section].map { EntrySection(section: section, entries: $0) }
        }
    }
}

// MARK: - Panel

struct PastePanelView: View {
    @ObservedObject var model: PastePanelModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            hairline
            if model.visible.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    HistoryListView(model: model)
                        .frame(width: Theme.Spotlight.listWidth)
                    hairline.frame(width: 0.5).frame(maxHeight: .infinity)
                    if let entry = model.selected {
                        EntryDetailView(model: model, entry: entry)
                    }
                }
            }
            hairline
            footer
        }
        .frame(width: Theme.Spotlight.width, height: Theme.Spotlight.height)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.spotlight, style: .continuous)
                .strokeBorder(Theme.rimHighlight, lineWidth: 0.5)
        )
        .scaleEffect(model.appeared ? 1 : 0.97)
        .opacity(model.appeared ? 1 : 0)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.border(scheme))
            .frame(height: 0.5)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.l) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            SearchField(model: model)
            Label("Clipboard", systemImage: "doc.on.clipboard")
                .font(Theme.caption(11))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.xs)
                .background(Capsule().fill(Theme.accent.opacity(0.14)))
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.Spotlight.searchHeight)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: model.totalCount == 0 ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(model.totalCount == 0 ? "Nothing copied yet" : "No results for “\(model.query)”")
                .font(Theme.title(14))
            Text(model.totalCount == 0
                 ? "Copy text, images or files and they show up here."
                 : "Try a different word, an app name or a file name.")
                .font(Theme.body(12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.l) {
            KeyHint(keys: ["↑", "↓"], label: "Navigate")
            KeyHint(keys: ["⏎"], label: "Paste")
            KeyHint(keys: ["⌘", "1–9"], label: "Paste as")
            KeyHint(keys: ["esc"], label: "Close")
            Spacer()
            Text(model.totalCount == 1 ? "1 item" : "\(model.totalCount) items")
                .font(Theme.caption(10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.Spotlight.footerHeight)
    }
}

// MARK: - History list

private struct HistoryListView: View {
    @ObservedObject var model: PastePanelModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.sections) { group in
                        Text(group.section.rawValue.uppercased())
                            .font(Theme.caption(9.5))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.top, Theme.Space.m)
                            .padding(.bottom, 2)
                        ForEach(group.entries) { entry in
                            HistoryRowView(model: model, entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, Theme.Space.s)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }
}

private struct HistoryRowView: View {
    @ObservedObject var model: PastePanelModel
    let entry: ClipboardEntry
    @Environment(\.colorScheme) private var scheme

    private var selected: Bool { model.selectedID == entry.id }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            EntryIcon(model: model, entry: entry, size: 22)
            Text(entry.title)
                .font(Theme.body(13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Space.s)
            Text(RelativeTime.short(entry.date))
                .font(Theme.caption(10.5))
                .monospacedDigit()
                .foregroundStyle(selected ? .secondary : .tertiary)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.Spotlight.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(selected ? Theme.selectionBorder : .clear, lineWidth: 1)
        )
        .animation(Theme.Motion.selection, value: selected)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { inside in
            if inside { model.hoveredID = entry.id } else if model.hoveredID == entry.id { model.hoveredID = nil }
        }
        .onTapGesture(count: 2) { model.pick(entry) }
        .onTapGesture { model.select(entry.id) }
    }

    private var fill: Color {
        if selected { return Theme.selectionFill(scheme) }
        return model.hoveredID == entry.id ? Theme.hoverFill(scheme) : .clear
    }
}

/// Image thumbnail, file icon, or a kind symbol.
private struct EntryIcon: View {
    @ObservedObject var model: PastePanelModel
    let entry: ClipboardEntry
    let size: CGFloat

    var body: some View {
        Group {
            switch entry.kind {
            case .image:
                if let image = model.thumbnail(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    symbol("photo")
                }
            case .files:
                if let url = entry.fileURLs.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: size, height: size)
                } else {
                    symbol("doc")
                }
            case .text:
                symbol(entry.looksLikeLink ? "link" : "text.alignleft")
            }
        }
        .frame(width: size, height: size)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.6, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.accent)
    }
}

extension ClipboardEntry {
    var looksLikeLink: Bool {
        guard kind == .text, let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace),
              let url = URL(string: text) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

// MARK: - Detail

private struct EntryDetailView: View {
    @ObservedObject var model: PastePanelModel
    let entry: ClipboardEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.border(scheme), lineWidth: 0.5)
                )
            metadata
            if !model.transforms.isEmpty {
                pasteAs
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.kind {
        case .text:
            ScrollView {
                Text(String((entry.text ?? "").prefix(4000)))
                    .font(entry.looksLikeLink ? Theme.body(13) : Theme.mono(12))
                    .foregroundStyle(.primary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Theme.Space.l)
            }
        case .image:
            if let image = model.thumbnail(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Image unavailable")
                    .font(Theme.body(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(entry.fileURLs, id: \.self) { url in
                        HStack(spacing: Theme.Space.m) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).font(Theme.body(12.5)).lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(Theme.caption(10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            metaRow("Source") {
                HStack(spacing: 5) {
                    if let icon = model.appIcon(for: entry) {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(entry.sourceApp ?? "Unknown")
                }
            }
            metaRow("Copied") { Text(entry.date.formatted(date: .abbreviated, time: .shortened)) }
            metaRow("Content") { Text(entry.detail) }
        }
    }

    private func metaRow(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(label)
                .font(Theme.caption(11))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
            value()
                .font(Theme.body(11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var pasteAs: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("PASTE AS")
                .font(Theme.caption(9.5))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, 2)
            ForEach(Array(model.transforms.prefix(9).enumerated()), id: \.element) { index, transform in
                TransformRowView(transform: transform, shortcut: index + 1) {
                    model.pickTransform(at: index)
                }
            }
        }
    }
}

private struct TransformRowView: View {
    let transform: PasteTransform
    let shortcut: Int
    let onPick: () -> Void

    @StateObject private var hover = HoverState()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: transform.symbolName)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(transform.title)
                .font(Theme.body(12.5))
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            KeyHint(keys: ["⌘", "\(shortcut)"], label: nil)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(hover.inside ? Theme.hoverFill(scheme) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hover.inside = $0 }
        .onTapGesture(perform: onPick)
    }
}

/// Per-row hover without `@State` (no SwiftUI macros on this toolchain).
private final class HoverState: ObservableObject {
    @Published var inside = false
}

// MARK: - Keycaps

/// `⌘` `1` style keycaps followed by an optional label.
struct KeyHint: View {
    let keys: [String]
    let label: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 17, minHeight: 16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                            .fill(Theme.keycapFill(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                            .strokeBorder(Theme.border(scheme), lineWidth: 0.5)
                    )
            }
            if let label {
                Text(label)
                    .font(Theme.caption(10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
        }
    }
}

enum RelativeTime {
    /// `now`, `5m`, `3h`, `2d` — compact enough for a trailing column.
    static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}
