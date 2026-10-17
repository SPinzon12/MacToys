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
        if Self.current === self {
            Self.current = nil
        }
    }

    // MARK: - Extraction

    /// The overlay closes right away; OCR runs off the main thread and the
    /// result lands on the clipboard (with its toast) when it is ready.
    private func extractRegion(_ rect: NSRect) {
        guard let crop = crop(rect) else {
            finish()
            return
        }
        finish()
        let ticket = Self.takeTicket()
        Task {
            let waiting = Self.showWaitingToastIfSlow()
            let text = await Task.detached(priority: .userInitiated) {
                ((try? OCRService.lines(in: OCRService.upscaledIfSmall(crop))) ?? [])
                    .joined(separator: "\n")
            }.value
            waiting.cancel()
            // Nothing recognized → leave the clipboard alone instead of emptying it.
            Self.deliver(
                text.isEmpty ? nil : text,
                ticket: ticket,
                confirmation: "Copied \(text.count) \(text.count == 1 ? "char" : "chars")",
                missMessage: "No text found"
            )
        }
    }

    private func extractWord(at point: NSPoint) {
        guard let capture else {
            finish()
            return
        }
        // View coords and Vision boxes are both y-up and normalized over the
        // same display, so the click maps straight onto the word boxes.
        let normalized = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
        finish()
        let ticket = Self.takeTicket()
        Task {
            // No prefetch on purpose: Vision serializes text requests, so a
            // background full-screen pass would delay every region drag.
            let waiting = Self.showWaitingToastIfSlow()
            let words = await Task.detached(priority: .userInitiated) {
                (try? OCRService.words(in: capture)) ?? []
            }.value
            waiting.cancel()
            Self.deliver(
                words.first(where: { $0.box.contains(normalized) })?.text,
                ticket: ticket,
                confirmation: "Copied word",
                missMessage: "No word under the cursor"
            )
        }
    }

    /// OCR is usually ~100 ms, but the first run of a new build can take ~26 s;
    /// past 400 ms a toast says it is working (the result toast replaces it).
    private static func showWaitingToastIfSlow() -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            Toast.show("Recognizing text…", leading: .symbol("hourglass"), hold: 60)
        }
    }

    /// Id of the newest extraction; results from older ones are dropped.
    private static var latestTicketID = 0

    private static func takeTicket() -> ExtractionTicket {
        latestTicketID += 1
        return ExtractionTicket(id: latestTicketID, changeCount: NSPasteboard.general.changeCount)
    }

    /// Copies `text` and confirms it with a toast reading `confirmation`, or
    /// shows `missMessage` when OCR found nothing — but only if the ticket is
    /// still the newest and the clipboard was not changed meanwhile.
    private static func deliver(_ text: String?, ticket: ExtractionTicket, confirmation: String, missMessage: String) {
        let pasteboard = NSPasteboard.general
        let verdict = ticket.verdict(latestID: latestTicketID, currentChangeCount: pasteboard.changeCount)
        guard verdict != .superseded else { return } // the newer extraction shows its own toasts
        guard let text else {
            Toast.show(missMessage, leading: .symbol("text.viewfinder"))
            return
        }
        guard verdict == .deliver else {
            // .clipboardChanged — also replaces a "Recognizing text…" pill that would linger.
            Toast.show("Kept your newer copy", leading: .symbol("doc.on.clipboard"))
            return
        }
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
