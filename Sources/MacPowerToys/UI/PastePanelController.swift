import AppKit
import SwiftUI

/// Borderless windows refuse key status by default; the panel needs keys
/// (typing, ↑/↓, Return, ⌘digits, Esc) while it is up.
private final class KeyablePanel: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Presents the Spotlight-style clipboard panel and resolves once the user
/// picks an entry / transform or dismisses it (Esc, click outside, focus loss).
@MainActor
final class PastePanelController: NSObject, NSWindowDelegate {
    static let shared = PastePanelController()

    private var window: NSWindow?
    private var keyMonitor: Any?
    private var model: PastePanelModel?
    private var continuation: CheckedContinuation<PastePanelPick?, Never>?

    private override init() {
        super.init()
    }

    func present(
        history: ClipboardHistory,
        contentFor: @escaping (ClipboardEntry) -> ClipboardContent,
        imageData: @escaping (ClipboardEntry) -> Data?
    ) async -> PastePanelPick? {
        // ⌃⇧V while the panel is up closes it, like Spotlight's own toggle.
        if continuation != nil {
            finish(nil)
            return nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<PastePanelPick?, Never>) in
            let model = PastePanelModel(history: history, contentFor: contentFor, imageData: imageData) { [weak self] pick in
                // Deferred: finish() closes the panel, then the coordinator pastes.
                Task { @MainActor in self?.finish(pick) }
            }
            self.model = model
            self.continuation = continuation

            let size = NSSize(width: Theme.Spotlight.width, height: Theme.Spotlight.height)
            let window = KeyablePanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true // follows the glass shape's alpha
            window.level = .statusBar
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            window.contentView = Self.glass(hosting: NSHostingView(rootView: PastePanelView(model: model)), size: size)
            window.delegate = self
            window.setFrameOrigin(Self.origin(for: size))
            window.alphaValue = 0
            self.window = window

            NSApp.activate() // brief activation so the panel can take keys
            window.makeKeyAndOrderFront(nil)
            window.invalidateShadow()
            if let field = Self.firstTextField(in: window.contentView) {
                window.makeFirstResponder(field)
            }
            installKeyMonitor()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.Motion.appearDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
            withAnimation(Theme.Motion.appear) { model.appeared = true }
        }
    }

    // MARK: - Glass

    /// Liquid Glass on macOS 26+, behind-window vibrancy before it. Either way
    /// the surface samples what is behind the window instead of faking it.
    private static func glass(hosting: NSView, size: NSSize) -> NSView {
        let radius = Theme.Radius.spotlight
        hosting.frame = NSRect(origin: .zero, size: size)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = radius
            glass.style = .regular
            glass.contentView = hosting
            return glass
        }
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: radius)
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        return effect
    }

    /// Stretchable rounded-rect mask: the documented way to round a
    /// behind-window `NSVisualEffectView` (layer corner radius does not clip it).
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }

    // MARK: - Dismissal

    private func finish(_ pick: PastePanelPick?) {
        guard let continuation else { return } // idempotent: first result wins
        self.continuation = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let window {
            window.delegate = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Theme.Motion.dismissDuration
                window.animator().alphaValue = 0
            }, completionHandler: {
                // AppKit runs the completion on the main thread, but the closure
                // type is not main-actor isolated.
                MainActor.assumeIsolated { window.orderOut(nil) }
            })
        }
        window = nil
        model = nil
        continuation.resume(returning: pick)
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(nil)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.model else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command,
               let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
               (1...9).contains(digit) {
                model.pickTransform(at: digit - 1)
                return nil
            }
            switch event.keyCode {
            case 53: // esc: clear the search first, close on the second press
                if model.query.isEmpty { self.finish(nil) } else { model.query = "" }
                return nil
            case 36, 76: // return / enter
                model.activate()
                return nil
            case 125: // down
                model.move(1)
                return nil
            case 126: // up
                model.move(-1)
                return nil
            default:
                return event // typing goes to the search field
            }
        }
    }

    // MARK: - Placement

    /// Centered horizontally, upper third of the screen under the cursor —
    /// where Spotlight sits.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        let x = visible.midX - size.width / 2
        let top = visible.maxY - visible.height * 0.18
        let y = max(visible.minY, top - size.height)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }
}

// MARK: - Search field

/// AppKit text field: SwiftUI's `TextField` focus needs `@FocusState`, a macro
/// this toolchain cannot compile.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: PastePanelModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Search clipboard history"
        field.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query {
            field.stringValue = model.query
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: PastePanelModel

        init(model: PastePanelModel) {
            self.model = model
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.query = field.stringValue
        }
    }
}
