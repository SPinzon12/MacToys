import AppKit
import Carbon

/// The Text Extractor overlay's content view: the captured display, a 50% dim
/// over it, a rubber-band selection that punches through the dim (accent
/// border, outer glow, corner handles, size chip), the hint line, and input
/// routing back to the session.
///
/// Layer-hosting on purpose: the capture and the dim are composited by the GPU
/// and a drag only swaps a few paths. The previous `draw(_:)` repainted the
/// whole retina capture on the CPU per mouse event (11–22 ms a frame at
/// 2940×1912, ~4× that on a 5K display).
final class RegionSelectionView: NSView {
    /// A drag shorter than this is a click and means word mode (PowerOCR ~4 px).
    static let dragThreshold: CGFloat = 4

    /// Live rubber-band in view coordinates (y-up); nil between gestures.
    var selection: NSRect? { didSet { updateSelectionLayers() } }
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

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let glowMask = CAShapeLayer()
    private let haloLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let chipLayer = CALayer()
    private let hintLayer = CALayer()

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        // Layer-hosting: assign the layer before turning on wantsLayer.
        layer = CALayer()
        wantsLayer = true
        setUpLayers()
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

    private func setUpLayers() {
        guard let root = layer else { return }
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.frame = bounds

        // The dim is one even-odd path: the full bounds plus the selection
        // hole, so the real pixels show through without a second image draw.
        dimLayer.frame = bounds
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
        dimLayer.fillRule = .evenOdd
        dimLayer.path = CGPath(rect: bounds, transform: nil)

        // Soft accent glow, kept outside the border by an even-odd mask so the
        // pixels inside stay untinted.
        glowLayer.frame = bounds
        glowLayer.fillColor = nil
        glowLayer.lineWidth = 2
        glowLayer.strokeColor = Theme.accentNS.withAlphaComponent(0.6).cgColor
        glowLayer.shadowColor = Theme.accentNS.cgColor
        glowLayer.shadowOpacity = 0.75
        glowLayer.shadowRadius = 7
        glowLayer.shadowOffset = .zero
        glowMask.frame = bounds
        glowMask.fillRule = .evenOdd
        glowLayer.mask = glowMask

        // Dark halo under an accent border: reads on bright and dark pixels.
        haloLayer.frame = bounds
        haloLayer.fillColor = nil
        haloLayer.lineWidth = 4
        haloLayer.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        borderLayer.frame = bounds
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.5
        borderLayer.strokeColor = Theme.accentNS.cgColor

        handlesLayer.frame = bounds
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = Theme.accentNS.cgColor
        handlesLayer.lineWidth = 1.5
        handlesLayer.shadowColor = NSColor.black.cgColor
        handlesLayer.shadowOpacity = 0.45
        handlesLayer.shadowRadius = 1.5
        handlesLayer.shadowOffset = CGSize(width: 0, height: -1)

        let hint = hintImage()
        hintLayer.contents = hint
        hintLayer.frame = CGRect(
            x: ((bounds.width - hint.size.width) / 2).rounded(),
            y: bounds.maxY - 52,
            width: hint.size.width,
            height: hint.size.height
        )

        for sublayer in [imageLayer, dimLayer, glowLayer, haloLayer, borderLayer, handlesLayer, chipLayer, hintLayer] {
            root.addSublayer(sublayer)
        }
        updateSelectionLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Vector layers rasterize at contentsScale; match the display so the
        // border and handles stay crisp on retina.
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in layer?.sublayers ?? [] {
            sublayer.contentsScale = scale
        }
        glowMask.contentsScale = scale
    }

    private func updateSelectionLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // no implicit fades while dragging
        defer { CATransaction.commit() }

        guard let selection else {
            dimLayer.path = CGPath(rect: bounds, transform: nil)
            for sublayer in [glowLayer, haloLayer, borderLayer, handlesLayer, chipLayer] {
                sublayer.isHidden = true
            }
            return
        }
        let radius = Self.cornerRadius
        let rounded = CGPath(roundedRect: selection, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let punched = CGMutablePath()
        punched.addRect(bounds)
        punched.addPath(rounded)

        dimLayer.path = punched
        glowMask.path = punched
        glowLayer.path = rounded
        haloLayer.path = rounded
        borderLayer.path = rounded
        handlesLayer.path = handlesPath(for: selection)

        let chip = chipImage(for: selection)
        chipLayer.contents = chip
        chipLayer.frame = chipFrame(size: chip.size, beside: selection)

        for sublayer in [glowLayer, haloLayer, borderLayer, handlesLayer, chipLayer] {
            sublayer.isHidden = false
        }
    }

    /// Crosshair while selecting: the pointer should not hide the pixels.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// Four corner handles, seated on the rounded corners' arcs. Empty on a
    /// selection too small to hold them without covering it.
    private func handlesPath(for rect: NSRect) -> CGPath? {
        guard rect.width >= 24, rect.height >= 24 else { return nil }
        // Where a 45° line from the corner meets a 6 pt corner arc.
        let inset = Self.cornerRadius * (1 - 1 / 2.squareRoot())
        let side: CGFloat = 8
        let corners = [
            CGPoint(x: rect.minX + inset, y: rect.minY + inset),
            CGPoint(x: rect.maxX - inset, y: rect.minY + inset),
            CGPoint(x: rect.minX + inset, y: rect.maxY - inset),
            CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        ]
        let path = CGMutablePath()
        for corner in corners {
            path.addEllipse(in: CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side))
        }
        return path
    }

    /// Corner radius of the selection's punch-through and border.
    private static let cornerRadius: CGFloat = 6

    /// Live `W × H` of the selection as a small image; only this re-renders
    /// per drag event.
    private func chipImage(for rect: NSRect) -> NSImage {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let size = NSSize(width: (textSize.width + padding * 2).rounded(.up), height: 22)
        return NSImage(size: size, flipped: false) { chip in
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6).fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            let border = NSBezierPath(roundedRect: chip.insetBy(dx: 0.25, dy: 0.25), xRadius: 6, yRadius: 6)
            border.lineWidth = 0.5
            border.stroke()
            text.draw(at: CGPoint(x: padding, y: (chip.height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
    }

    /// Parked beside the selection, flipped to the other side to stay on screen.
    private func chipFrame(size: NSSize, beside rect: NSRect) -> CGRect {
        var origin = CGPoint(x: rect.maxX + 8, y: rect.maxY - size.height - 6)
        if origin.x + size.width > bounds.maxX {
            origin.x = rect.minX - size.width - 8
        }
        if origin.y < bounds.minY { origin.y = rect.minY + 6 }
        return CGRect(origin: origin, size: size)
    }

    /// The bottom-center hint pill, rendered once per session.
    private func hintImage() -> NSImage {
        let text = "drag to select · click a word · esc" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
        let textSize = text.size(withAttributes: attributes)
        let symbolSide: CGFloat = 15
        let gap: CGFloat = 7
        let padding: CGFloat = 14
        let pillHeight = max(textSize.height + 14, 30)
        let size = NSSize(width: (symbolSide + gap + textSize.width + padding * 2).rounded(.up), height: pillHeight.rounded(.up))
        let symbol = Self.tintedSymbol("text.viewfinder", side: symbolSide)
        return NSImage(size: size, flipped: false) { pill in
            let radius = pill.height / 2
            NSColor.black.withAlphaComponent(0.62).setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            NSColor.white.withAlphaComponent(0.14).setStroke()
            let border = NSBezierPath(roundedRect: pill.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
            border.lineWidth = 0.5
            border.stroke()
            symbol?.draw(in: CGRect(x: padding, y: pill.midY - symbolSide / 2, width: symbolSide, height: symbolSide))
            text.draw(
                at: CGPoint(x: padding + symbolSide + gap, y: pill.midY - textSize.height / 2),
                withAttributes: attributes
            )
            return true
        }
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
