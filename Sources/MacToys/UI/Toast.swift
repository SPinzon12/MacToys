import AppKit
import QuartzCore
import SwiftUI

/// Copy-confirmation HUD: a small glass pill centered near the top of the
/// display under the mouse. It fades and scales in, holds, then fades out; a
/// new toast replaces one that is still showing.
///
/// The window is a non-activating, click-through panel, so it never takes
/// focus or a click from the frontmost app.
@MainActor
enum Toast {
    /// What sits before the message: an SF Symbol or a color dot.
    enum Leading {
        case symbol(String)
        case swatch(NSColor)
    }

    /// `hold` is how long the pill stays before fading; a later toast always
    /// replaces it, so a long hold suits a "working…" message.
    static func show(
        _ message: String,
        leading: Leading = .symbol("checkmark.circle.fill"),
        hold: TimeInterval = 1.0
    ) {
        ToastController.shared.show(message: message, leading: leading, hold: hold)
    }
}

// MARK: - Controller

/// Owns the single toast panel and its show/hold/hide sequence.
@MainActor
private final class ToastController {
    static let shared = ToastController()

    private enum Timing {
        static let fadeIn: TimeInterval = 0.12
        static let fadeOut: TimeInterval = 0.25
        /// Starting scale of the entrance; the pill settles to 1.
        static let startScale: CGFloat = 0.94
    }

    /// Gap between the top of the visible frame (below the menu bar) and the pill.
    private static let topInset: CGFloat = 28
    private static let height: CGFloat = 34

    private var panel: ToastPanel?
    private var container: NSView?
    private var glass: NSVisualEffectView?
    private var host: NSHostingView<ToastPill>?
    /// The running show/hold/hide sequence; cancelled when a new toast replaces it.
    private var sequence: Task<Void, Never>?

    func show(message: String, leading: Toast.Leading, hold: TimeInterval) {
        sequence?.cancel()
        let panel = makePanelIfNeeded()
        guard let container, let glass, let host else { return }

        host.rootView = ToastPill(message: message, leading: leading)
        let width = ceil(max(host.fittingSize.width, Self.height))
        let size = NSSize(width: width, height: Self.height)

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.maxY - Self.topInset - size.height).rounded()
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        container.frame = NSRect(origin: .zero, size: size)
        glass.frame = container.bounds
        glass.maskImage = Self.capsuleMask(height: size.height)
        host.frame = container.bounds
        panel.invalidateShadow()

        // A replaced toast keeps its current alpha and fades on from there, so
        // the swap reads as one pill updating rather than a flicker.
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless() // shows without activating the app
        animateScale(of: container)

        Self.fade(panel, to: 1, duration: Timing.fadeIn, curve: .easeOut)

        sequence = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Timing.fadeIn + hold))
            guard !Task.isCancelled, let self, let panel = self.panel else { return }
            Self.fade(panel, to: 0, duration: Timing.fadeOut, curve: .easeIn)
            try? await Task.sleep(for: .seconds(Timing.fadeOut))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    /// Window-alpha fade. Synchronous on purpose: inside the async sequence
    /// `runAnimationGroup` would otherwise resolve to its awaiting overload.
    private static func fade(
        _ panel: NSPanel,
        to alpha: CGFloat,
        duration: TimeInterval,
        curve: CAMediaTimingFunctionName
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: curve)
            panel.animator().alphaValue = alpha
        }
    }

    /// Entrance scale about the pill's center. Presentation-only: the layer's
    /// model transform stays identity, so nothing is left scaled if it is cut short.
    private func animateScale(of view: NSView) {
        guard let layer = view.layer else { return }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let s = Timing.startScale
        // AppKit-backed layers anchor at (0, 0): scale, then shift back to center.
        let from = CATransform3DConcat(
            CATransform3DMakeScale(s, s, 1),
            CATransform3DMakeTranslation(center.x * (1 - s), center.y * (1 - s), 0)
        )
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = Timing.fadeIn
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "toast.scale")
    }

    private func makePanelIfNeeded() -> ToastPanel {
        if let panel { return panel }

        let panel = ToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.height, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true // click-through: never intercepts the user
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: panel.contentLayoutRect)
        container.wantsLayer = true

        // Behind-window glass: samples whatever is under the pill.
        let glass = NSVisualEffectView(frame: container.bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        container.addSubview(glass)

        let host = NSHostingView(rootView: ToastPill(message: "", leading: .symbol("checkmark")))
        container.addSubview(host)

        panel.contentView = container
        self.panel = panel
        self.container = container
        self.glass = glass
        self.host = host
        return panel
    }

    /// Stretchable capsule mask: the cap insets keep the round ends round at
    /// any width.
    private static func capsuleMask(height: CGFloat) -> NSImage {
        let radius = height / 2
        let image = NSImage(size: NSSize(width: height + 1, height: height), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Never key, never main: the toast must not take focus from anyone.
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Pill

/// The pill's content, drawn over the glass: leading mark, message, and the
/// hairline + rim-highlight edge of the shared glass idiom.
private struct ToastPill: View {
    let message: String
    let leading: Toast.Leading

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            leadingMark
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 15)
        .frame(height: 34)
        .overlay(Capsule().strokeBorder(Theme.border(scheme), lineWidth: 0.5))
        .overlay(Capsule().strokeBorder(Theme.rimHighlight, lineWidth: 0.5))
    }

    @ViewBuilder private var leadingMark: some View {
        switch leading {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
        case .swatch(let color):
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(Theme.border(scheme), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        }
    }
}
