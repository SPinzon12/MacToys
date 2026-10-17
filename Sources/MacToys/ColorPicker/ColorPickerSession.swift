import AppKit
import ApplicationServices

/// Shared Color Picker numbers, so capture and lens rendering always agree.
enum ColorPickerSpec {
    /// Neighborhood sampled around the cursor. Odd on purpose: the cursor pixel
    /// is exactly at index `samplePixels / 2`.
    static let samplePixels = 25
    /// Magnification in physical screen pixels (8×).
    static let zoom = 8
}

/// One Color Picker overlay session: a borderless window spanning every display,
/// a 60 Hz timer sampling the pixel under the cursor, and a magnifier lens.
/// Left-click copies `#RRGGBB` to the clipboard and ends the session;
/// Esc, right-click, or re-triggering the hotkey cancels it.
@MainActor
final class ColorPickerSession: NSObject {
    /// The live session, if any. `ColorPickerSession` toggles against this —
    /// sessions are never stacked.
    static var current: ColorPickerSession?

    static func start() {
        let session = ColorPickerSession()
        current = session
        session.begin()
    }

    private var window: OverlayWindow?
    private var lensView: LensView?
    private var timer: Timer?
    private var hex: String?
    /// The color behind `hex`, kept only to tint the copy toast's swatch.
    private var color: NSColor?
    private var reportedCaptureFailure = false

    private override init() {
        super.init()
    }

    func begin() {
        // Runtime fallback: the Permissions window opens at launch, this catches
        // the session itself (permission revoked since launch, denied elsewhere).
        guard CGPreflightScreenCaptureAccess() else {
            finish()
            presentCaptureAlert()
            return
        }
        guard let primary = NSScreen.screens.first else {
            finish()
            return
        }

        // One window unioned over every display: a click anywhere is a pick,
        // and there is a single overlay to position and tear down.
        var frame = primary.frame
        for screen in NSScreen.screens.dropFirst() {
            frame = frame.union(screen.frame)
        }

        let view = LensView(frame: NSRect(origin: .zero, size: frame.size))
        view.onPick = { [weak self] in self?.pick() }
        view.onCancel = { [weak self] in self?.finish() }

        let window = OverlayWindow(
            contentRect: frame, // borderless: frame == content rect
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false // must catch the pick click and Esc
        window.isReleasedWhenClosed = false
        window.contentView = view

        self.window = window
        lensView = view

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(view) // Esc lands in keyDown

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        tick() // first frame without waiting a beat
    }

    /// Ends the session. Safe to call twice; also the cancel path.
    func finish() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        lensView = nil
        hex = nil
        color = nil
        if Self.current === self {
            Self.current = nil
        }
    }

    private func pick() {
        if let hex {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            _ = pasteboard.setString(hex, forType: .string)
            Toast.show("Copied \(hex)", leading: color.map(Toast.Leading.swatch) ?? .symbol("eyedropper"))
        }
        finish()
    }

    // MARK: - Sampling

    @objc private func tick() {
        guard let window, let view = lensView else { return }

        let mouse = NSEvent.mouseLocation // AppKit global, y-up
        let cursor = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
        let cg = cgPoint(fromAppKit: mouse)
        let display = display(at: cg)
        // Pixel grid is integer-aligned in CG space; floor = the pixel under the cursor.
        let pixelX = cg.x.rounded(.down)
        let pixelY = cg.y.rounded(.down)
        let half = CGFloat(ColorPickerSpec.samplePixels / 2)

        // ponytail: this capture API (C: CGDisplayCreateImageForRect, Swift name
        // CGDisplayCreateImage(_:rect:)) is SCREEN_CAPTURE_OBSOLETE in the macOS
        // 15 SDK; ScreenCaptureKit is the upgrade path when it dies — an
        // SCStream/frame sampler with the same 1×1 read path.
        // Exact pixel under the cursor: a 1×1 capture, so no averaging can leak in.
        guard
            let pixelImage = CGDisplayCreateImage(
                display,
                rect: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)
            ),
            let rgba = Self.rgbaPixel(of: pixelImage),
            // Neighborhood for the lens, centered on that same pixel.
            let lensImage = CGDisplayCreateImage(
                display,
                rect: CGRect(
                    x: pixelX - half,
                    y: pixelY - half,
                    width: CGFloat(ColorPickerSpec.samplePixels),
                    height: CGFloat(ColorPickerSpec.samplePixels)
                )
            )
        else {
            captureFailed()
            return
        }

        let hex = String(format: "#%02X%02X%02X", rgba.r, rgba.g, rgba.b)
        self.hex = hex
        let color = NSColor(
            srgbRed: CGFloat(rgba.r) / 255,
            green: CGFloat(rgba.g) / 255,
            blue: CGFloat(rgba.b) / 255,
            alpha: 1
        )
        self.color = color
        view.show(image: lensImage, hex: hex, color: color, cursor: cursor)
    }

    /// AppKit's origin is the bottom-left of the primary screen; CG global
    /// coordinates start at the top-left of the same screen, y growing downward.
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

    /// Reads a 1×1 capture as RGB. Drawing into a known-format context avoids
    /// guessing the capture's native byte order or bit depth.
    private static func rgbaPixel(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drew else { return nil }
        // Display pixels are opaque, so premultiplication leaves RGB untouched.
        return (bytes[0], bytes[1], bytes[2])
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
        The Color Picker needs Screen Recording access to sample screen pixels. \
        Grant it under System Settings → Privacy & Security → Screen Recording, \
        then relaunch MacToys.
        """
        alert.addButton(withTitle: "Fix Permissions…")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            // The window requests the permission (which lists MacToys in System
            // Settings) and offers the relaunch Screen Recording needs.
            PermissionsWindowController.shared.show()
        }
    }
}

/// Borderless overlay that can become key — a plain NSWindow refuses, and a
/// window that is never key never receives Esc.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
