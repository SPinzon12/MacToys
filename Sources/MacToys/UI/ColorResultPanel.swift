import AppKit
import SwiftUI

// MARK: - Model
//
// ponytail: no `@State` — SwiftUI macros do not compile on this toolchain.

final class ColorResultModel: ObservableObject {
    @Published var color: PickedColor
    /// The format last copied; its row shows "Copied".
    @Published var copiedFormat: ColorFormat
    @Published var history: [PickedColor]

    var onCopy: (ColorFormat) -> Void = { _ in }
    var onPickAgain: () -> Void = {}
    var onRecent: (PickedColor) -> Void = { _ in }

    init(color: PickedColor, copiedFormat: ColorFormat, history: [PickedColor]) {
        self.color = color
        self.copiedFormat = copiedFormat
        self.history = history
    }
}

// MARK: - View

struct ColorResultView: View {
    @ObservedObject var model: ColorResultModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 2) {
                ForEach(ColorFormat.allCases, id: \.self) { format in
                    FormatRow(
                        format: format,
                        value: model.color.string(in: format),
                        copied: format == model.copiedFormat
                    ) { model.onCopy(format) }
                }
            }
            if model.history.count > 1 {
                recent
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: model.color.nsColor))
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color(nsColor: model.color.nsColor).opacity(0.45), radius: 10, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Label("Copied \(model.color.string(in: model.copiedFormat))", systemImage: "checkmark.circle.fill")
                    .font(Theme.title(13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("≈ \(ColorNames.nearest(to: model.color))")
                    .font(Theme.body(12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(Theme.caption(9.5))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            HStack(spacing: 7) {
                ForEach(model.history, id: \.self) { color in
                    Button { model.onRecent(color) } label: {
                        Circle()
                            .fill(Color(nsColor: color.nsColor))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                            .overlay(
                                Circle()
                                    .strokeBorder(Theme.accent, lineWidth: 2)
                                    .padding(-3)
                                    .opacity(color == model.color ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.string(in: .hex))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: model.onPickAgain) {
                Label("Pick Again", systemImage: "eyedropper.halffull")
                    .font(Theme.caption(11.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            KeyHint(keys: ["⌘", "P"], label: nil)
            Spacer()
            KeyHint(keys: ["esc"], label: "Close")
        }
    }
}

private struct FormatRow: View {
    let format: ColorFormat
    let value: String
    let copied: Bool
    let action: () -> Void

    @StateObject private var hover = RowHover()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(format.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                Text(value)
                    .font(Theme.mono(13))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied ? Theme.accent : Color.secondary)
                    .opacity(copied || hover.inside ? 1 : 0.5)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hover.inside ? Theme.hoverFill(scheme) : Theme.cardFill(scheme).opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.inside = $0 }
        .help("Copy \(format.title) — and use it by default")
    }
}

private final class RowHover: ObservableObject {
    @Published var inside = false
}

// MARK: - Window

private final class ColorResultKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows the card next to where the color was picked. Non-activating key panel
/// (the Spotlight model): the app you were in keeps focus.
@MainActor
final class ColorResultPanelController {
    static let shared = ColorResultPanelController()

    private var window: NSPanel?
    private var model: ColorResultModel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private init() {}

    func show(
        color: PickedColor,
        copiedFormat: ColorFormat,
        history: [PickedColor],
        onPickAgain: @escaping () -> Void,
        onRecent: @escaping (PickedColor) -> Void
    ) {
        close()
        let model = ColorResultModel(color: color, copiedFormat: copiedFormat, history: history)
        model.onCopy = { [weak model] format in
            guard let model else { return }
            ColorPickerController.copy(model.color.string(in: format))
            ColorFormat.saved = format // the format you copy becomes the default
            model.copiedFormat = format
        }
        model.onPickAgain = onPickAgain
        model.onRecent = onRecent
        self.model = model

        let host = NSHostingView(rootView: ColorResultView(model: model))
        host.layout()
        let size = host.fittingSize
        let panel = ColorResultKeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = GlassSurface.make(hosting: host, size: size, radius: 16)
        panel.setFrameOrigin(Self.origin(for: size))
        panel.alphaValue = 0
        window = panel
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.appearDuration
            panel.animator().alphaValue = 1
        }
        installMonitors(for: panel)
    }

    func update(color: PickedColor, copiedFormat: ColorFormat, history: [PickedColor]) {
        model?.color = color
        model?.copiedFormat = copiedFormat
        model?.history = history
    }

    func close(animated: Bool = true) {
        for monitor in [keyMonitor, clickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        clickMonitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        guard let window else { return }
        self.window = nil
        model = nil
        guard animated else {
            window.orderOut(nil)
            CATransaction.flush() // out of the next screen capture right now
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.Motion.dismissDuration
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        })
    }

    private func installMonitors(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, MainActor.assumeIsolated({ event.window === self.window }) else { return event }
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            if event.keyCode == 53 { // esc
                MainActor.assumeIsolated { self.close() }
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "p" {
                MainActor.assumeIsolated { self.model?.onPickAgain() }
                return nil
            }
            return event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Down-right of the pointer (where the color was just picked), kept on its screen.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        // Grown by a point: NSMouseInRect excludes the top/right edges, so a pick on
        // a display's top row would otherwise match no screen.
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame.insetBy(dx: -1, dy: -1), false) }
            ?? NSScreen.main
        var x = mouse.x + 18
        var y = mouse.y - size.height - 18
        if let visible = screen?.visibleFrame {
            if x + size.width > visible.maxX { x = mouse.x - size.width - 18 }
            if y < visible.minY { y = mouse.y + 18 }
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }
}
