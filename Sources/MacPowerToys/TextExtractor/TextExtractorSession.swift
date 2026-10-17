import AppKit
import ApplicationServices

/// One Text Extractor session: capture the main display once, show it dimmed
/// behind a borderless overlay, then either OCR the dragged region into the
/// clipboard or copy the word under a plain click. Esc, right-click, or
/// re-triggering the hotkey cancels it; sessions never stack.
@MainActor
final class TextExtractorSession: NSObject {
    /// The live session, if any. `TextExtractorSession` toggles against this.
    static var current: TextExtractorSession?

    static func start() {
        let session = TextExtractorSession()
        current = session
        session.begin()
    }

    private var window: OverlayWindow?
    private var selectionView: RegionSelectionView?
    private var capture: CGImage?
    /// View size in points; the capture maps onto it 1:1 (both cover the display).
    private var bounds = NSRect.zero
    /// Word boxes from OCR of the full capture, kept after the first click so a
    /// second click is instant.
    private var cachedWords: [OCRService.Word]?
    private var reportedCaptureFailure = false

    private override init() {
        super.init()
    }

    func begin() {
        // Runtime fallback: Permissions.preflight() warns at launch; this catches
        // the session itself (permission revoked since launch, denied elsewhere).
        guard CGPreflightScreenCaptureAccess() else {
            finish()
            presentCaptureAlert()
            return
        }
        guard let screen = Self.screen(for: CGMainDisplayID()) else {
            finish()
            return // no display to overlay; nothing to explain
        }

        // One capture of the main display, taken now — the overlay shows it for
        // as long as the session lasts, even if the live screen changes under it.
        // ponytail: same SCREEN_CAPTURE_OBSOLETE API the Color Picker uses;
        // ScreenCaptureKit is the upgrade path when the deployment target moves.
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            captureFailed()
            return
        }

        capture = image
        bounds = NSRect(origin: .zero, size: screen.frame.size)

        let view = RegionSelectionView(frame: bounds, image: image)
        view.onSelectRegion = { [weak self] rect in self?.extractRegion(rect) }
        view.onSelectWord = { [weak self] point in self?.extractWord(at: point) }
        view.onCancel = { [weak self] in self?.finish() }

        // One window over the main display only: that is the display we captured,
        // so overlay coordinates and capture pixels stay in lockstep.
        let window = OverlayWindow(
            contentRect: screen.frame, // borderless: frame == content rect
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false // must catch the drag, the click and Esc
        window.isReleasedWhenClosed = false
        window.contentView = view

        self.window = window
        selectionView = view

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(view) // Esc lands in keyDown
    }

    /// Ends the session. Safe to call twice; also the cancel path.
    func finish() {
        window?.orderOut(nil)
        window = nil
        selectionView = nil
        capture = nil
        cachedWords = nil
        if Self.current === self {
            Self.current = nil
        }
    }

    // MARK: - Extraction

    private func extractRegion(_ rect: NSRect) {
        guard let crop = crop(rect) else {
            finish()
            return
        }
        // ponytail: Vision runs on the main thread — one blocking pass per
        // region; move it off-main only if the wait ever feels stuck.
        let lines = (try? OCRService.lines(in: OCRService.upscaledIfSmall(crop))) ?? []
        let text = lines.joined(separator: "\n")
        // Nothing recognized → leave the clipboard alone instead of emptying it.
        if !text.isEmpty {
            copy(text, confirmation: "Copied \(text.count) \(text.count == 1 ? "char" : "chars")")
        }
        finish()
    }

    private func extractWord(at point: NSPoint) {
        guard let capture else {
            finish()
            return
        }
        if cachedWords == nil {
            // ponytail: one full-screen OCR per session, blocking; cached so a
            // second click does not pay for it again.
            cachedWords = (try? OCRService.words(in: capture)) ?? []
        }
        // View coords and Vision boxes are both y-up and normalized over the
        // same display, so the click maps straight onto the word boxes.
        let normalized = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
        if let word = cachedWords?.first(where: { $0.box.contains(normalized) }) {
            copy(word.text, confirmation: "Copied word")
        }
        finish()
    }

    /// Copies `text` and confirms it with a toast reading `confirmation`.
    private func copy(_ text: String, confirmation: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(text, forType: .string)
        Toast.show(confirmation, leading: .symbol("text.viewfinder"))
    }

    /// View rect (y-up, origin bottom-left) → image pixels (y-down, origin top-left).
    private func crop(_ rect: NSRect) -> CGImage? {
        guard let capture else { return nil }
        let viewRect = rect.intersection(bounds)
        guard !viewRect.isNull, viewRect.width >= 1, viewRect.height >= 1 else { return nil }

        let scaleX = CGFloat(capture.width) / bounds.width
        let scaleY = CGFloat(capture.height) / bounds.height
        let imageRect = CGRect(
            x: viewRect.minX * scaleX,
            y: (bounds.maxY - viewRect.maxY) * scaleY, // the y-flip, back to image space
            width: viewRect.width * scaleX,
            height: viewRect.height * scaleY
        )
        let clamped = imageRect.integral.intersection(
            CGRect(x: 0, y: 0, width: capture.width, height: capture.height)
        )
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return capture.cropping(to: clamped)
    }

    // MARK: - Plumbing

    /// The NSScreen that owns `displayID`, so the overlay is placed on exactly
    /// the display that was captured.
    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }
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
        The Text Extractor needs Screen Recording access to capture the screen \
        for OCR. Grant it under System Settings → Privacy & Security → Screen \
        Recording, then relaunch Mac PowerToys.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            _ = NSWorkspace.shared.open(url)
        }
    }
}

/// Borderless overlay that can become key — a plain NSWindow refuses, and a
/// window that is never key never receives Esc.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
