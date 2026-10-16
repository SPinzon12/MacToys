import AppKit
import SwiftUI

// MARK: - UI-side metadata
//
// Everything here is presentation. The tested transform logic
// (`Transforms/PasteTransform.swift`) stays untouched: grouping and icons are
// UI concerns, so they live in this file as an extension.

enum PasteGroup: String, CaseIterable, Identifiable {
    case text
    case files
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "TEXT"
        case .files: "FILES"
        case .media: "MEDIA"
        }
    }
}

extension PasteTransform {
    var group: PasteGroup {
        switch self {
        case .plainText, .imageToText, .structuredToJSON, .htmlToMarkdown: .text
        case .txtFile, .pngFile, .htmlFile: .files
        case .videoToMP4, .audioToM4A: .media
        }
    }

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

// MARK: - Models
//
// ponytail: no `@State`/`@Observable` — this CommandLineTools-only toolchain
// ships no SwiftUIMacros plugin, so SwiftUI macros do not compile. Mutable UI
// state lives in `ObservableObject` classes instead, which are plain Swift.
// They are deliberately not actor-isolated: every touch happens on the main
// thread (panel construction, hover, key handling).

final class PasteRowModel: ObservableObject, Identifiable {
    let transform: PasteTransform
    @Published var hovered = false

    var id: String { transform.rawValue }

    init(_ transform: PasteTransform) {
        self.transform = transform
    }
}

final class PastePanelModel: ObservableObject {
    let rows: [PasteRowModel]
    let preview: String
    @Published var selectedIndex = 0

    private let onPick: (PasteTransform) -> Void

    init(rows: [PasteRowModel], preview: String, onPick: @escaping (PasteTransform) -> Void) {
        self.rows = rows
        self.preview = preview
        self.onPick = onPick
    }

    func pick(_ transform: PasteTransform) {
        onPick(transform)
    }

    func activate() {
        guard rows.indices.contains(selectedIndex) else { return }
        pick(rows[selectedIndex].transform)
    }

    func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + rows.count) % rows.count
    }
}

// MARK: - View

struct PastePanelView: View {
    @ObservedObject var model: PastePanelModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            header
            ForEach(PasteGroup.allCases) { group in
                let groupRows = model.rows.filter { $0.transform.group == group }
                if !groupRows.isEmpty {
                    section(group, groupRows)
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(width: 272)
        .background(glass)
        .padding(PastePanelView.shadowRoom) // room so the shadow is not clipped
    }

    static let shadowRoom: CGFloat = 20

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text("ADVANCED PASTE")
                .font(Theme.caption(9.5))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.Space.s)
            Text(model.preview)
                .font(Theme.caption(10))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.cardFill(scheme))
                )
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.xs)
    }

    private func section(_ group: PasteGroup, _ rows: [PasteRowModel]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(group.title)
                .font(Theme.caption(9))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.xs)
            ForEach(rows) { row in
                PasteRowView(
                    row: row,
                    selected: model.rows.firstIndex(where: { $0 === row }) == model.selectedIndex
                ) {
                    model.pick(row.transform)
                }
            }
        }
    }

    private var glass: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.baseFill(scheme).opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.border(scheme), lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.rimHighlight, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
    }
}

struct PasteRowView: View {
    @ObservedObject var row: PasteRowModel
    let selected: Bool
    let onPick: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: row.transform.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(row.transform.title)
                .font(Theme.body())
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 5)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.accent.opacity(selected ? 0.5 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { row.hovered = $0 }
        .onTapGesture(perform: onPick)
    }

    private var fill: Color {
        if selected { return Theme.selectedFill(scheme) }
        return row.hovered ? Theme.hoverFill(scheme) : .clear
    }
}

// MARK: - Window

/// Borderless panels refuse key status by default; the panel needs keys
/// (↑/↓/Return/Esc) while it is up.
private final class KeyablePanel: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Presents the panel at the cursor and resolves once the user picks a
/// transform or dismisses it (Esc, click outside, or focus loss).
@MainActor
final class PastePanelController: NSObject, NSWindowDelegate {
    static let shared = PastePanelController()

    private var window: NSWindow?
    private var keyMonitor: Any?
    private var model: PastePanelModel?
    private var continuation: CheckedContinuation<PasteTransform?, Never>?

    private override init() {
        super.init()
    }

    func present(rows: [PasteRowModel], preview: String) async -> PasteTransform? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PasteTransform?, Never>) in
            let model = PastePanelModel(rows: rows, preview: preview) { [weak self] transform in
                // Deferred: finish() closes the panel, then the coordinator runs the transform.
                Task { @MainActor in self?.finish(transform) }
            }
            self.model = model
            self.continuation = continuation

            let host = NSHostingView(rootView: PastePanelView(model: model))
            host.layout()
            let size = host.fittingSize

            let window = KeyablePanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false // the SwiftUI surface draws its own
            window.level = .statusBar
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .transient]
            window.contentView = host
            window.delegate = self
            window.setFrameOrigin(Self.origin(for: size))
            self.window = window

            NSApp.activate() // brief activation so the panel can take keys
            window.makeKeyAndOrderFront(nil)
            installKeyMonitor()
        }
    }

    // MARK: - Dismissal

    private func finish(_ transform: PasteTransform?) {
        guard let continuation else { return } // idempotent: first result wins
        self.continuation = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        model = nil
        continuation.resume(returning: transform)
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(nil)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // esc
                self.finish(nil)
                return nil
            case 36, 76: // return / enter
                self.model?.activate()
                return nil
            case 125, 48: // down / tab
                self.model?.move(1)
                return nil
            case 126: // up
                self.model?.move(-1)
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - Placement

    /// Panel top-left lands just below-right of the cursor, clamped to the
    /// screen the cursor is on. `shadowRoom` keeps the glass itself at the
    /// cursor rather than the padded hosting view.
    private static func origin(for size: NSSize) -> NSPoint {
        let pad = PastePanelView.shadowRoom
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var x = mouse.x - pad
        var y = mouse.y - size.height + pad - 4
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX), max(visible.minX, visible.maxX - size.width))
            y = min(max(y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        return NSPoint(x: x, y: y)
    }
}
