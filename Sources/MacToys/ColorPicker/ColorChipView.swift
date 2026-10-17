import AppKit
import Carbon

/// PowerToys-style picker overlay: the cursor stays as it is, and a small glass
/// chip floats beside it with the color under it and its code. Scrolling up
/// grows a magnifier on top of the chip; scrolling back down hides it again.
///
/// The view fills a window unioned over every display, so the chip is clamped
/// to the display under the cursor rather than to the whole desktop.
final class ColorChipView: NSView {
    var onPick: (() -> Void)?
    var onCancel: (() -> Void)?
    /// +1 per wheel notch up, -1 down.
    var onZoom: ((Int) -> Void)?

    private var color = PickedColor(r: 0, g: 0, b: 0)
    private var cursor = NSPoint.zero
    private var loupe: (image: CGImage, factor: Int)?

    override var acceptsFirstResponder: Bool { true }
    /// The pick click must count even if the overlay was not key yet.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// One sampling frame. `loupe` is nil while the magnifier is off.
    func show(color: PickedColor, cursor: NSPoint, loupe: (image: CGImage, factor: Int)?) {
        self.color = color
        self.cursor = cursor
        self.loupe = loupe
        needsDisplay = true
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) { onPick?() }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: onCancel?()
        case kVK_Return, kVK_ANSI_KeypadEnter: onPick?()
        default: super.keyDown(with: event)
        }
    }

    /// One zoom step per gesture notch; trackpads send many small deltas, so
    /// they accumulate until a notch's worth has scrolled.
    private var scrollAccumulator: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
        scrollAccumulator += delta
        while abs(scrollAccumulator) >= 1 {
            let step = scrollAccumulator > 0 ? 1 : -1
            scrollAccumulator -= CGFloat(step)
            onZoom?(step)
        }
    }

    // MARK: - Drawing

    static let loupePoints: CGFloat = 132
    private static let pad: CGFloat = 8
    private static let chipHeight: CGFloat = 34
    private static let swatchSide: CGFloat = 22
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    override func draw(_ dirtyRect: NSRect) {
        // The cursor sits beside the chip, over "nothing": an invisible 1% veil
        // makes sure the pick click and the wheel land on this overlay instead of
        // falling through fully transparent pixels to the app underneath.
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill()

        let value = color.string(in: ColorFormat.saved) as NSString
        let valueWidth = value.size(withAttributes: [.font: Self.valueFont]).width.rounded(.up)
        let chipWidth = Self.pad + Self.swatchSide + 9 + valueWidth + 12
        let hasLoupe = loupe != nil
        let width = hasLoupe ? max(chipWidth, Self.loupePoints + Self.pad * 2) : chipWidth
        let height = Self.chipHeight + (hasLoupe ? Self.loupePoints + Self.pad : 0)
        let card = placement(for: CGSize(width: width, height: height))

        // Glass-dark card with a hairline and a soft lift, like the app's other HUDs.
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSColor(white: 0.11, alpha: 0.9).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        if let loupe {
            let loupeRect = CGRect(
                x: card.midX - Self.loupePoints / 2,
                y: card.maxY - Self.pad - Self.loupePoints,
                width: Self.loupePoints,
                height: Self.loupePoints
            )
            drawLoupe(loupe.image, factor: loupe.factor, in: loupeRect)
        }

        // Chip row: swatch + value in the default format.
        let swatchRect = CGRect(
            x: card.minX + Self.pad,
            y: card.minY + (Self.chipHeight - Self.swatchSide) / 2,
            width: Self.swatchSide,
            height: Self.swatchSide
        )
        let swatch = NSBezierPath(roundedRect: swatchRect, xRadius: 6, yRadius: 6)
        color.nsColor.setFill()
        swatch.fill()
        swatch.lineWidth = 1
        NSColor.white.withAlphaComponent(0.3).setStroke()
        swatch.stroke()
        let valueSize = value.size(withAttributes: [.font: Self.valueFont])
        value.draw(
            at: CGPoint(x: swatchRect.maxX + 9, y: swatchRect.midY - valueSize.height / 2),
            withAttributes: [.font: Self.valueFont, .foregroundColor: NSColor.white]
        )

        drawHint()
    }

    /// Down-right of the cursor (PowerToys' spot), flipped near the right or
    /// bottom edge of the display under the cursor.
    private func placement(for size: CGSize) -> CGRect {
        let area = screenRect(containing: cursor) ?? bounds
        let offset: CGFloat = 16
        var x = cursor.x + offset
        var y = cursor.y - offset - size.height
        if x + size.width > area.maxX - 4 { x = cursor.x - offset - size.width }
        if y < area.minY + 4 { y = cursor.y + offset }
        x = min(max(x, area.minX + 4), area.maxX - size.width - 4)
        y = min(max(y, area.minY + 4), area.maxY - size.height - 4)
        let scale = window?.backingScaleFactor ?? 2
        return CGRect(x: (x * scale).rounded() / scale, y: (y * scale).rounded() / scale, width: size.width, height: size.height)
    }

    private func drawLoupe(_ image: CGImage, factor: Int, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        let pixelPoints = CGFloat(factor) / scale
        let side = CGFloat(image.width) * pixelPoints
        // The capture is a little larger than the loupe; center it so the
        // cursor's pixel lands in the middle.
        let imageRect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let clip = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)

        context.saveGState()
        context.addPath(clip)
        context.clip()
        context.interpolationQuality = .none // hard pixel edges
        context.draw(image, in: imageRect)
        if pixelPoints >= 4 {
            drawGrid(in: imageRect, pixelPoints: pixelPoints, scale: scale)
        }
        // The cursor's pixel, outlined dark then light so it reads on any color.
        let cell = CGRect(x: rect.midX - pixelPoints / 2, y: rect.midY - pixelPoints / 2, width: pixelPoints, height: pixelPoints)
        let dark = NSBezierPath(rect: cell.insetBy(dx: -1.5, dy: -1.5))
        dark.lineWidth = 1.5
        NSColor.black.withAlphaComponent(0.7).setStroke()
        dark.stroke()
        let light = NSBezierPath(rect: cell.insetBy(dx: -0.25, dy: -0.25))
        light.lineWidth = 1
        NSColor.white.setStroke()
        light.stroke()
        context.restoreGState()

        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        border.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.25).setStroke()
        border.stroke()

        let zoomLabel = "\(factor)×" as NSString
        let font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        let size = zoomLabel.size(withAttributes: [.font: font])
        let tag = CGRect(x: rect.maxX - size.width - 12, y: rect.maxY - size.height - 8, width: size.width + 8, height: size.height + 2)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: tag, xRadius: 4, yRadius: 4).fill()
        zoomLabel.draw(at: CGPoint(x: tag.minX + 4, y: tag.minY + 1), withAttributes: [.font: font, .foregroundColor: NSColor.white])
    }

    /// One physical pixel wide, on whole physical pixels, so it stays sharp.
    private func drawGrid(in rect: CGRect, pixelPoints: CGFloat, scale: CGFloat) {
        let hairline = 1 / scale
        let grid = NSBezierPath()
        var x = rect.minX + pixelPoints
        while x < rect.maxX {
            grid.move(to: CGPoint(x: x + hairline / 2, y: rect.minY))
            grid.line(to: CGPoint(x: x + hairline / 2, y: rect.maxY))
            x += pixelPoints
        }
        var y = rect.minY + pixelPoints
        while y < rect.maxY {
            grid.move(to: CGPoint(x: rect.minX, y: y + hairline / 2))
            grid.line(to: CGPoint(x: rect.maxX, y: y + hairline / 2))
            y += pixelPoints
        }
        grid.lineWidth = hairline
        NSColor.black.withAlphaComponent(0.16).setStroke()
        grid.stroke()
    }

    /// Bottom-center of the cursor's display: how to use it, once, quietly.
    private func drawHint() {
        let area = screenRect(containing: cursor) ?? bounds
        let text = "click to copy  ·  scroll to zoom  ·  esc" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let size = text.size(withAttributes: attributes)
        let pill = CGRect(x: area.midX - size.width / 2 - 14, y: area.minY + 36, width: size.width + 28, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 6), withAttributes: attributes)
    }

    /// The frame, in this view's coordinates, of the display containing `point`.
    private func screenRect(containing point: CGPoint) -> CGRect? {
        guard let window else { return nil }
        let global = window.convertPoint(toScreen: convert(point, to: nil))
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(global, $0.frame.insetBy(dx: -1, dy: -1), false)
        }) else { return nil }
        return convert(window.convertFromScreen(screen.frame), from: nil)
    }
}
