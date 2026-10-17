import AppKit
import SwiftUI

/// The three hotkey modules, as the panel shows them.
enum PanelModule: CaseIterable {
    case colorPicker
    case textExtractor
    case clipboard

    var title: String {
        switch self {
        case .colorPicker: "Color Picker"
        case .textExtractor: "Text Extractor"
        case .clipboard: "Clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .colorPicker: "eyedropper.halffull"
        case .textExtractor: "text.viewfinder"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var keys: [String] {
        switch self {
        case .colorPicker: ["⌃", "⇧", "C"]
        case .textExtractor: ["⌃", "⇧", "O"]
        case .clipboard: ["⌃", "⇧", "V"]
        }
    }
}

// MARK: - Model
//
// ponytail: no `@State`/`@Observable` — SwiftUI macros do not compile on this
// CommandLineTools toolchain. State lives in an ObservableObject, touched only
// from the main thread.

final class MenuPanelModel: ObservableObject {
    @Published var keepAwake: KeepAwakeSession?
    @Published var allowDisplaySleep = false
    @Published var permissions = PermissionStatus(screenRecording: true, accessibility: true)
    @Published var launchAtLogin = false
    @Published var launchAtLoginAvailable = false
    /// Ticks once a second while the panel is open, for the countdown.
    @Published var now = Date()
    let version: String

    var onModule: (PanelModule) -> Void = { _ in }
    var onKeepAwake: (KeepAwakeDuration?) -> Void = { _ in } // nil = turn off
    var onExtendKeepAwake: () -> Void = {}
    var onAllowDisplaySleep: (Bool) -> Void = { _ in }
    var onLaunchAtLogin: () -> Void = {}
    var onPermissions: () -> Void = {}
    var onClearHistory: () -> Void = {}
    var onQuit: () -> Void = {}

    init(version: String) {
        self.version = version
    }
}

// MARK: - Views

struct MenuPanelView: View {
    @ObservedObject var model: MenuPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 8) {
                ForEach(PanelModule.allCases, id: \.self) { module in
                    ModuleCard(module: module) { model.onModule(module) }
                }
            }
            KeepAwakeCard(model: model)
            footer
        }
        .padding(14)
        .frame(width: MenuPanelView.width)
    }

    static let width: CGFloat = 352

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: BrandGlyph.menuBar(pointSize: 26))
                .renderingMode(.template)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacToys").font(Theme.title(14))
                Text(model.version).font(Theme.caption(10.5)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: model.onPermissions) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.permissions.allGranted ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(model.permissions.summary).font(Theme.caption(11))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Permissions")
        }
    }

    private var footer: some View {
        // Permissions live in the header chip; the footer keeps the rest.
        HStack(spacing: 4) {
            FooterButton(title: "Clear History", symbol: "trash", action: model.onClearHistory)
            if model.launchAtLoginAvailable {
                FooterButton(
                    title: "Open at Login",
                    symbol: model.launchAtLogin ? "checkmark.circle.fill" : "circle",
                    action: model.onLaunchAtLogin
                )
            }
            Spacer()
            FooterButton(title: "Quit", symbol: "power", action: model.onQuit)
        }
    }
}

private struct ModuleCard: View {
    let module: PanelModule
    let action: () -> Void

    @StateObject private var hover = PanelHover()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: module.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .frame(height: 24)
                Text(module.title)
                    .font(Theme.title(11.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                KeyHint(keys: module.keys, label: nil)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hover.inside ? Theme.hoverFill(scheme) : Theme.cardFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border(scheme), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.inside = $0 }
        .animation(Theme.Motion.selection, value: hover.inside)
    }
}

private struct KeepAwakeCard: View {
    @ObservedObject var model: MenuPanelModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: model.keepAwake == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.keepAwake == nil ? Color.secondary : Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake").font(Theme.title(13))
                    Text(KeepAwakeSession.cardSubtitle(model.keepAwake, now: model.now))
                        .font(Theme.caption(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.keepAwake != nil },
                    set: { model.onKeepAwake($0 ? .indefinitely : nil) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            HStack(spacing: 6) {
                ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                    Chip(title: duration.shortTitle, selected: model.keepAwake?.duration == duration) {
                        model.onKeepAwake(duration)
                    }
                }
                if model.keepAwake?.canExtend == true {
                    Chip(title: "+15m", selected: false, action: model.onExtendKeepAwake)
                        .help("Add 15 minutes")
                }
            }
            Toggle("Allow display to sleep", isOn: Binding(
                get: { model.allowDisplaySleep },
                set: { model.onAllowDisplaySleep($0) }
            ))
            .toggleStyle(.checkbox)
            .font(Theme.caption(11))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(model.keepAwake == nil ? Theme.border(scheme) : Theme.selectionBorder, lineWidth: model.keepAwake == nil ? 0.5 : 1)
        )
        .animation(Theme.Motion.selection, value: model.keepAwake == nil)
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(minWidth: 34)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Theme.accent : Theme.keycapFill(scheme))
                )
                .overlay(Capsule().strokeBorder(Theme.border(scheme), lineWidth: selected ? 0 : 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @StateObject private var hover = PanelHover()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.caption(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hover.inside ? Theme.hoverFill(scheme) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.inside = $0 }
    }
}

/// Per-view hover without `@State` (no SwiftUI macros on this toolchain).
private final class PanelHover: ObservableObject {
    @Published var inside = false
}

// MARK: - Window

/// Borderless panels refuse key status by default; buttons and switches need it.
private final class MenuKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Drops below the status item like Control Center; closes on Esc, on a click
/// outside, or when the status item is clicked again.
@MainActor
final class MenuPanelController {
    let model: MenuPanelModel
    private var window: NSPanel?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var tick: Timer?

    init(model: MenuPanelModel) {
        self.model = model
    }

    var isShown: Bool { window?.isVisible == true }

    func toggle(below button: NSStatusBarButton) {
        isShown ? close() : show(below: button)
    }

    func show(below button: NSStatusBarButton) {
        model.now = Date()
        let host = NSHostingView(rootView: MenuPanelView(model: model))
        host.layout()
        let size = host.fittingSize
        let panel = MenuKeyablePanel(
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
        panel.setFrameOrigin(Self.origin(for: size, below: button))
        panel.alphaValue = 0
        window = panel

        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.appearDuration
            panel.animator().alphaValue = 1
        }
        installMonitors(button: button)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    func close() {
        tick?.invalidate()
        tick = nil
        for monitor in [outsideClickMonitor, keyMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitor = nil
        keyMonitor = nil
        guard let window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.Motion.dismissDuration
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        })
    }

    private func installMonitors(button: NSStatusBarButton) {
        // Clicks in other apps: global monitor. The status item's own click is
        // handled by its action (toggle), so it is not treated as "outside".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // esc
            MainActor.assumeIsolated { self?.close() }
            return nil
        }
    }

    /// Top edge just under the status item, centered on it, kept on screen.
    private static func origin(for size: NSSize, below button: NSStatusBarButton) -> NSPoint {
        guard let buttonWindow = button.window else { return .zero }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - size.width / 2
        let y = anchor.minY - size.height - 6
        if let visible = buttonWindow.screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }
}
