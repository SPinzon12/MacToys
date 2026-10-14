import AppKit
import Carbon

/// The Text Extractor overlay's content view: the captured display, a 50% dim
/// over it, a rubber-band selection that punches through the dim, the hint
/// line, and input routing back to the session.
final class RegionSelectionView: NSView {
    /// A drag shorter than this is a click and means word mode (PowerOCR ~4 px).
    static let dragThreshold: CGFloat = 4

    /// Live rubber-band in view coordinates (y-up); nil between gestures.
    var selection: NSRect? { didSet { needsDisplay = true } }
    /// Dragged far enough: OCR this rect and copy the recognized text.
    var onSelectRegion: ((NSRect) -> Void)?
    /// A plain click: copy the word under the cursor.
    var onSelectWord: ((NSPoint) -> Void)?
    /// Esc or right-click: cancel.
    var onCancel: (() -> Void)?

    /// The display capture this view draws; it maps 1:1 onto the view bounds.
    private let image: CGImage
    /// mouseDown anchor, held until mouseUp decides click vs drag.
    private var anchor: NSPoint?

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        selection = Self.rect(from: anchor, to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard let anchor else { return }
        let end = convert(event.locationInWindow, from: nil)
        let distance = hypot(end.x - anchor.x, end.y - anchor.y)
        self.anchor = nil
        if distance >= Self.dragThreshold, let selection {
            onSelectRegion?(selection)
        } else {
            onSelectWord?(end)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // The capture, then dimmed: the overlay must read as "about to select".
        context.draw(image, in: bounds)
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(rect: bounds).fill()

        if let selection {
            // Punch through the dim so the drag shows the real pixels.
            context.saveGState()
            context.clip(to: selection)
            context.draw(image, in: bounds)
            context.restoreGState()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }

        drawHint()
    }

    private func drawHint() {
        let text = "drag to select · click a word · Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.maxY - 44)
        let pill = CGRect(
            x: origin.x - 14,
            y: origin.y - 7,
            width: size.width + 28,
            height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    /// Standardized rect between two view points (handles any drag direction).
    private static func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
