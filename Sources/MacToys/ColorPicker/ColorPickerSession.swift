import AppKit

/// One Color Picker session (PowerToys-style): a transparent window over every
/// display catches the click, Esc and the scroll wheel; a 60 Hz timer samples
/// the pixel under the cursor for the chip beside it, plus the neighborhood
/// for the magnifier while zoom is on. The cursor itself is left alone.
@MainActor
final class ColorPickerSession: NSObject {
    private var window: OverlayWindow?
    private var chipView: ColorChipView?
    private var timer: Timer?
    private var zoom = PickerZoom()
    private var color: PickedColor?
    private var reportedCaptureFailure = false
    private let onPicked: (PickedColor) -> Void
    private let onEnded: () -> Void

    init(onPicked: @escaping (PickedColor) -> Void, onEnded: @escaping () -> Void) {
        self.onPicked = onPicked
        self.onEnded = onEnded
        super.init()
    }

    func begin() {
        // Runtime fallback: the Permissions window opens at launch; this catches
        // a permission revoked since then or denied elsewhere.
        guard CGPreflightScreenCaptureAccess() else {
            finish()
            presentCaptureAlert()
            return
        }
        guard let primary = NSScreen.screens.first else {
            finish()
            return
        }
        // One window unioned over every display: a click anywhere is a pick.
        var frame = primary.frame
        for screen in NSScreen.screens.dropFirst() {
            frame = frame.union(screen.frame)
        }
        let view = ColorChipView(frame: NSRect(origin: .zero, size: frame.size))
        view.onPick = { [weak self] in self?.pick() }
        view.onCancel = { [weak self] in self?.finish() }
        view.onZoom = { [weak self] step in
            self?.zoom.step(by: step)
            self?.tick() // redraw at the new zoom right away
        }

        let window = OverlayWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false // must catch the click, the wheel and Esc
        window.isReleasedWhenClosed = false
        window.contentView = view
        self.window = window
        chipView = view

        // Non-activating key panel: it becomes key (so Esc works) even when macOS
        // refuses to activate MacToys — measured: with a plain window the app
        // stayed inactive and the overlay never became key.
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(view)

        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick() // first frame without waiting a beat
    }

    /// Ends the session (cancel path too). Safe to call twice.
    func finish() {
        timer?.invalidate()
        timer = nil
        guard let window else { return }
        window.orderOut(nil)
        CATransaction.flush() // gone before anything else captures the screen
        self.window = nil
        chipView = nil
        onEnded()
    }

    private func pick() {
        let picked = color
        finish()
        if let picked { onPicked(picked) }
    }

    // MARK: - Sampling

    @objc private func tick() {
        guard let window, let view = chipView else { return }
        let mouse = NSEvent.mouseLocation // AppKit global, y-up
        let cursor = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
        let cg = cgPoint(fromAppKit: mouse)
        let display = display(at: cg)
        // Pixel grid is integer-aligned in CG space; floor = the pixel under the cursor.
        let pixelX = cg.x.rounded(.down)
        let pixelY = cg.y.rounded(.down)

        // ponytail: CGDisplayCreateImage(_:rect:) is SCREEN_CAPTURE_OBSOLETE in
        // the macOS 15 SDK; ScreenCaptureKit is the upgrade path when it dies.
        // Exact pixel under the cursor: a 1×1 capture, so no averaging leaks in.
        guard
            let pixelImage = CGDisplayCreateImage(display, rect: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)),
            let rgba = Self.rgbaPixel(of: pixelImage)
        else {
            captureFailed()
            return
        }
        let color = PickedColor(r: rgba.r, g: rgba.g, b: rgba.b)
        self.color = color

        var loupe: (image: CGImage, factor: Int)?
        if let factor = zoom.factor {
            let scale = window.screen?.backingScaleFactor ?? 2
            let side = PickerZoom.capturePixels(loupePoints: ColorChipView.loupePoints, scale: scale, factor: factor)
            let half = CGFloat(side / 2)
            let rect = CGRect(x: pixelX - half, y: pixelY - half, width: CGFloat(side), height: CGFloat(side))
            if let image = CGDisplayCreateImage(display, rect: rect) {
                loupe = (image, factor)
            }
        }
        view.show(color: color, cursor: cursor, loupe: loupe)
    }

    /// AppKit's origin is the bottom-left of the primary screen; CG global
    /// coordinates start at its top-left, y growing downward.
    private func cgPoint(fromAppKit point: NSPoint) -> CGPoint {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: primaryTop - point.y)
    }

    private func display(at point: CGPoint) -> CGDirectDisplayID {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 {
            return displayID
        }
        return CGMainDisplayID()
    }

    /// Reads a 1×1 capture as RGB through a known-format context.
    private static func rgbaPixel(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        // Display pixels are opaque, so premultiplication leaves RGB untouched.
        return drew ? (bytes[0], bytes[1], bytes[2]) : nil
    }

    private func captureFailed() {
        guard !reportedCaptureFailure else { return }
        reportedCaptureFailure = true // exactly one alert per session
        finish()
        presentCaptureAlert()
    }

    private func presentCaptureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = """
        The Color Picker reads the pixels under the cursor, which needs Screen \
        Recording access. Fix it in the Permissions window, then relaunch MacToys.
        """
        alert.addButton(withTitle: "Fix Permissions…")
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsWindowController.shared.show()
        }
    }
}

/// Borderless overlay that can become key without activating the app — a
/// window that is never key never receives Esc.
private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
