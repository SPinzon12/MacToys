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
            // Punch through the dim so the drag shows the real pixels, rounded
            // to match the selection chrome drawn over it.
            let rounded = NSBezierPath(roundedRect: selection, xRadius: 6, yRadius: 6)
            context.saveGState()
            context.addPath(CGPath(roundedRect: selection, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.clip()
            context.draw(image, in: bounds)
            context.restoreGState()

            // Dark halo under an accent border: reads on bright and dark pixels.
            rounded.lineWidth = 4
            NSColor.black.withAlphaComponent(0.35).setStroke()
            rounded.stroke()
            rounded.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            rounded.stroke()

            drawSizeChip(for: selection)
        }

        drawHint()
    }

    /// Crosshair while selecting: the pointer should not hide the pixels.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// Live `W × H` of the selection, parked beside it and kept on screen.
    private func drawSizeChip(for rect: NSRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let chipHeight: CGFloat = 22
        var origin = CGPoint(x: rect.maxX + 8, y: rect.maxY - chipHeight - 6)
        if origin.x + size.width + padding * 2 > bounds.maxX {
            origin.x = rect.minX - size.width - padding * 2 - 8
        }
        if origin.y < bounds.minY { origin.y = rect.minY + 6 }

        let chip = CGRect(x: origin.x, y: origin.y, width: size.width + padding * 2, height: chipHeight)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let chipBorder = NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6)
        chipBorder.lineWidth = 0.5
        chipBorder.stroke()
        text.draw(
            at: CGPoint(x: chip.minX + padding, y: chip.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawHint() {
        let text = "drag to select · click a word · esc" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
        let textSize = text.size(withAttributes: attributes)
        let symbolSide: CGFloat = 15
        let gap: CGFloat = 7
        let padding: CGFloat = 14
        let contentWidth = symbolSide + gap + textSize.width
        let pillHeight = max(textSize.height + 14, 30)
        let pill = CGRect(
            x: (bounds.width - (contentWidth + padding * 2)) / 2,
            y: bounds.maxY - 52,
            width: contentWidth + padding * 2,
            height: pillHeight
        )

        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        border.lineWidth = 0.5
        border.stroke()

        if let symbol = Self.tintedSymbol("text.viewfinder", side: symbolSide) {
            symbol.draw(in: CGRect(
                x: pill.minX + padding,
                y: pill.midY - symbolSide / 2,
                width: symbolSide,
                height: symbolSide
            ))
        }
        text.draw(
            at: CGPoint(x: pill.minX + padding + symbolSide + gap, y: pill.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    /// A white silhouette of an SF Symbol, for drawing on the dark pill.
    static func tintedSymbol(_ name: String, side: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configured = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: side - 2, weight: .medium)
        ) ?? base
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
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
