import AppKit
import Carbon

/// The overlay's content view: a round loupe centered on the cursor (magnified
/// pixels, pixel grid, the sampled pixel outlined, a ring painted in the
/// sampled color) and a glass card with the value in HEX, RGB or HSL.
///
/// The view fills a window unioned over every display, so the card is clamped
/// against the full desktop rather than one screen.
final class LensView: NSView {
    /// Left-click or Return: copy the value in the selected format.
    var onPick: (() -> Void)?
    /// Esc or right-click: cancel.
    var onCancel: (() -> Void)?

    private var lensImage: CGImage?
    private var rgb: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)
    /// Cursor position in view coordinates (y-up), from the session's sample tick.
    private var cursor = NSPoint.zero
    /// ⇥ / ← → cycle it; remembered for the next session.
    private(set) var format = ColorFormat.saved

    override var acceptsFirstResponder: Bool { true }

    /// The text a pick copies.
    var currentValue: String { format.string(r: rgb.r, g: rgb.g, b: rgb.b) }

    /// Pushes one sampling frame into the lens.
    func show(image: CGImage, rgb: (r: UInt8, g: UInt8, b: UInt8), cursor: NSPoint) {
        lensImage = image
        self.rgb = rgb
        self.cursor = cursor
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onPick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            onCancel?()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onPick?()
        case kVK_Tab where event.modifierFlags.contains(.shift), kVK_LeftArrow:
            select(format.previous)
        case kVK_Tab, kVK_RightArrow:
            select(format.next)
        default:
            super.keyDown(with: event)
        }
    }

    private func select(_ newFormat: ColorFormat) {
        format = newFormat
        ColorFormat.saved = newFormat
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let lensImage else { return }
        let scale = window?.backingScaleFactor ?? 2
        // Points per captured pixel: ColorPickerSpec.zoom physical pixels on
        // both Retina (2×) and non-Retina displays.
        let pixelPoints = CGFloat(ColorPickerSpec.zoom) / scale
        let diameter = CGFloat(ColorPickerSpec.samplePixels) * pixelPoints
        // Snap to device pixels so magnified pixels land on whole physical pixels.
        let center = CGPoint(
            x: (cursor.x * scale).rounded() / scale,
            y: (cursor.y * scale).rounded() / scale
        )
        let loupe = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        drawLoupe(lensImage, in: loupe, pixelPoints: pixelPoints, scale: scale)
        drawCard(below: loupe)
    }

    private var sampled: NSColor {
        NSColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
    }

    private func drawLoupe(_ image: CGImage, in rect: CGRect, pixelPoints: CGFloat, scale: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let ringWidth: CGFloat = 8
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2))

        // Lifted off the screen it magnifies.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -ringWidth, dy: -ringWidth)).fill()
        NSGraphicsContext.restoreGraphicsState()

        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        // Nearest-neighbor: the loupe must show hard pixel edges, not smoothing.
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        if pixelPoints > 1 {
            drawPixelGrid(in: rect, pixelPoints: pixelPoints, scale: scale)
        }
        drawCenterPixel(in: rect, pixelPoints: pixelPoints)
        context.restoreGState()

        // The ring takes the sampled color: the pick is visible at a glance.
        ring.lineWidth = ringWidth
        sampled.setStroke()
        ring.stroke()
        // Hairlines either side keep the ring legible on any background.
        let outer = NSBezierPath(ovalIn: rect.insetBy(dx: -ringWidth, dy: -ringWidth))
        outer.lineWidth = 1
        NSColor.black.withAlphaComponent(0.45).setStroke()
        outer.stroke()
        let inner = NSBezierPath(ovalIn: rect)
        inner.lineWidth = 1
        NSColor.white.withAlphaComponent(0.55).setStroke()
        inner.stroke()
    }

    /// Per-pixel grid, one physical pixel wide and centered on a physical pixel
    /// so it renders hard instead of as a two-pixel blur.
    private func drawPixelGrid(in rect: CGRect, pixelPoints: CGFloat, scale: CGFloat) {
        let hairline = 1 / scale
        let offset = hairline / 2
        let grid = NSBezierPath()
        var gx = rect.minX + pixelPoints
        while gx < rect.maxX - 0.5 {
            grid.move(to: CGPoint(x: gx + offset, y: rect.minY))
            grid.line(to: CGPoint(x: gx + offset, y: rect.maxY))
            gx += pixelPoints
        }
        var gy = rect.minY + pixelPoints
        while gy < rect.maxY - 0.5 {
            grid.move(to: CGPoint(x: rect.minX, y: gy + offset))
            grid.line(to: CGPoint(x: rect.maxX, y: gy + offset))
            gy += pixelPoints
        }
        grid.lineWidth = hairline
        NSColor.black.withAlphaComponent(0.18).setStroke()
        grid.stroke()
    }

    /// The sampled pixel: a white square inside a dark one, readable on any color.
    private func drawCenterPixel(in rect: CGRect, pixelPoints: CGFloat) {
        let half = CGFloat(ColorPickerSpec.samplePixels / 2)
        let cell = CGRect(
            x: rect.minX + half * pixelPoints,
            y: rect.minY + half * pixelPoints,
            width: pixelPoints,
            height: pixelPoints
        )
        let darkOutline = NSBezierPath(rect: cell.insetBy(dx: -1.5, dy: -1.5))
        darkOutline.lineWidth = 1.5
        NSColor.black.withAlphaComponent(0.75).setStroke()
        darkOutline.stroke()
        let lightOutline = NSBezierPath(rect: cell.insetBy(dx: -0.25, dy: -0.25))
        lightOutline.lineWidth = 1
        NSColor.white.setStroke()
        lightOutline.stroke()
    }

    // MARK: - Card

    /// The frame, in this view's coordinates, of the display containing `point`.
    private func screenRect(containing point: CGPoint) -> CGRect? {
        guard let window else { return nil }
        let global = window.convertPoint(toScreen: convert(point, to: nil))
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(global, $0.frame, false) }) else { return nil }
        let inWindow = window.convertFromScreen(screen.frame)
        return convert(inWindow, from: nil)
    }

    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
    private static let chipFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    private static let hintFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    private static let pad: CGFloat = 12
    private static let swatchSide: CGFloat = 38

    /// Sized for the widest possible value so the card never resizes while moving.
    /// Explicit worst cases: white is not the widest HSL (that is a 3-digit hue).
    private static let valueWidth: CGFloat = {
        ["#FFFFFF", "rgb(255, 255, 255)", "hsl(359, 100%, 100%)"]
            .map { ($0 as NSString).size(withAttributes: [.font: valueFont]).width }
            .max()!
            .rounded(.up)
    }()

    private func drawCard(below loupe: CGRect) {
        let pad = Self.pad
        let textX = pad + Self.swatchSide + 10
        let width = textX + max(Self.valueWidth, 150) + pad
        let height: CGFloat = 84
        let gap: CGFloat = 16

        // Keep the card on the display under the cursor: the view spans every
        // display, and with mismatched heights its bounds include dead gaps.
        let area = screenRect(containing: CGPoint(x: loupe.midX, y: loupe.midY)) ?? bounds
        var origin = CGPoint(x: loupe.midX - width / 2, y: loupe.minY - gap - height)
        if origin.y < area.minY + 4 { origin.y = loupe.maxY + gap } // no room below: above
        origin.x = min(max(origin.x, area.minX + 4), area.maxX - width - 4)
        let card = CGRect(origin: origin, size: CGSize(width: width, height: height))
        let shape = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
        NSColor(white: 0.10, alpha: 0.88).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        // Swatch.
        let swatchRect = CGRect(
            x: card.minX + pad,
            y: card.maxY - pad - Self.swatchSide,
            width: Self.swatchSide,
            height: Self.swatchSide
        )
        let swatch = NSBezierPath(roundedRect: swatchRect, xRadius: 8, yRadius: 8)
        sampled.setFill()
        swatch.fill()
        swatch.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        swatch.stroke()

        // Value in the selected format, top-aligned with the swatch.
        let value = currentValue as NSString
        let valueSize = value.size(withAttributes: [.font: Self.valueFont])
        value.draw(
            at: CGPoint(x: card.minX + textX, y: swatchRect.maxY - valueSize.height + 1),
            withAttributes: [.font: Self.valueFont, .foregroundColor: NSColor.white]
        )

        // Format chips on the swatch's bottom edge, the selected one in the brand accent.
        var chipX = card.minX + textX
        let chipY = swatchRect.minY
        for option in ColorFormat.allCases {
            let title = option.title as NSString
            let size = title.size(withAttributes: [.font: Self.chipFont])
            let chip = CGRect(x: chipX, y: chipY, width: size.width + 12, height: 17)
            let selected = option == format
            (selected ? Theme.accentNS : NSColor.white.withAlphaComponent(0.10)).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 8.5, yRadius: 8.5).fill()
            title.draw(
                at: CGPoint(x: chip.minX + 6, y: chip.midY - size.height / 2),
                withAttributes: [
                    .font: Self.chipFont,
                    .foregroundColor: NSColor.white.withAlphaComponent(selected ? 1 : 0.6)
                ]
            )
            chipX = chip.maxX + 5
        }

        let hint = "click to copy · ⇥ format · esc" as NSString
        hint.draw(
            at: CGPoint(x: card.minX + pad, y: card.minY + 8),
            withAttributes: [.font: Self.hintFont, .foregroundColor: NSColor.white.withAlphaComponent(0.45)]
        )
    }
}
