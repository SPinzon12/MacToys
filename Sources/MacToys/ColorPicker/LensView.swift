import AppKit
import Carbon

/// The overlay's content view: draws the magnifier lens (magnified pixels,
/// pixel grid, crosshair, color swatch, HEX + `rgb(...)` readout) and routes
/// input back to the session.
///
/// The view fills a window unioned over every display, so lens anchoring is
/// clamped against the full desktop rather than one screen.
final class LensView: NSView {
    /// Left-click: copy the HEX under the cursor.
    var onPick: (() -> Void)?
    /// Esc or right-click: cancel.
    var onCancel: (() -> Void)?

    private var lensImage: CGImage?
    private var hex = ""
    private var color = NSColor.black
    /// Cursor position in view coordinates (y-up), from the session's sample tick.
    private var cursor = NSPoint.zero

    override var acceptsFirstResponder: Bool { true }

    /// Pushes one sampling frame into the lens.
    func show(image: CGImage, hex: String, color: NSColor, cursor: NSPoint) {
        lensImage = image
        self.hex = hex
        self.color = color
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
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let lensImage else { return }

        let scale = window?.backingScaleFactor ?? 2
        // Points per captured pixel: keeps the magnification at ColorPickerSpec.zoom
        // physical pixels on both Retina (2×) and non-Retina displays.
        let pixelPoints = CGFloat(ColorPickerSpec.zoom) / scale
        let imageSize = CGFloat(ColorPickerSpec.samplePixels) * pixelPoints
        let pad: CGFloat = 7
        let gap: CGFloat = 9
        let swatchSide: CGFloat = 34
        // The readout row can be wider than the magnified image (Retina: 100 pt
        // image vs ~160 pt of swatch + "rgb(255, 255, 255)"), so the card takes
        // the wider of the two and centers the image.
        let readoutWidth = swatchSide + Self.textGap + Self.widestReadoutText
        let contentWidth = max(imageSize, readoutWidth)
        let lensWidth = contentWidth + pad * 2
        let lensHeight = pad + imageSize + gap + swatchSide + pad

        // Anchor up-right of the cursor; flip to the other side at the desktop
        // edge, then clamp so the lens never leaves the (multi-display) bounds.
        var origin = CGPoint(x: cursor.x + 14, y: cursor.y + 14)
        if origin.x + lensWidth > bounds.maxX {
            origin.x = cursor.x - 14 - lensWidth
        }
        if origin.y + lensHeight > bounds.maxY {
            origin.y = cursor.y - 14 - lensHeight
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - lensWidth)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - lensHeight)
        // Snap to device pixels: magnified pixels and grid lines then land on
        // whole physical pixels instead of smearing across two.
        origin.x = (origin.x * scale).rounded() / scale
        origin.y = (origin.y * scale).rounded() / scale

        let lensRect = CGRect(x: origin.x, y: origin.y, width: lensWidth, height: lensHeight)
        let card = NSBezierPath(roundedRect: lensRect, xRadius: Self.cardRadius, yRadius: Self.cardRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
        NSColor.black.withAlphaComponent(0.76).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        card.lineWidth = 0.5
        card.stroke()

        // Centered, then snapped to a device pixel like the origin above.
        let imageInset = (((contentWidth - imageSize) / 2) * scale).rounded() / scale
        let imageRect = CGRect(
            x: origin.x + pad + imageInset,
            y: origin.y + lensHeight - pad - imageSize,
            width: imageSize,
            height: imageSize
        )
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let imageClip = CGPath(
            roundedRect: imageRect,
            cornerWidth: Self.imageRadius,
            cornerHeight: Self.imageRadius,
            transform: nil
        )
        context.saveGState()
        context.addPath(imageClip)
        context.clip()
        // Nearest-neighbor: the lens must show hard pixel edges, not smoothing.
        context.interpolationQuality = .none
        context.draw(lensImage, in: imageRect)
        if pixelPoints > 1 {
            drawPixelGrid(in: imageRect, pixelPoints: pixelPoints, scale: scale)
        }
        drawCrosshair(in: imageRect, pixelPoints: pixelPoints)
        context.restoreGState()

        let imageBorder = NSBezierPath(
            roundedRect: imageRect.insetBy(dx: 0.25, dy: 0.25),
            xRadius: Self.imageRadius,
            yRadius: Self.imageRadius
        )
        imageBorder.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.3).setStroke()
        imageBorder.stroke()

        drawReadout(origin: CGPoint(x: origin.x + pad, y: origin.y + pad), swatchSide: swatchSide)

        drawHint()
    }

    private static let cardRadius: CGFloat = 12
    private static let imageRadius: CGFloat = 7

    private static let hexFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
    private static let rgbFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
    /// Space between the swatch and the text column.
    private static let textGap: CGFloat = 9

    /// Width of the widest possible readout line, measured once: sizing to the
    /// worst case keeps the card from resizing as the color under the cursor changes.
    private static let widestReadoutText: CGFloat = {
        let hex = ("#FFFFFF" as NSString).size(withAttributes: [.font: hexFont]).width
        let rgb = ("rgb(255, 255, 255)" as NSString).size(withAttributes: [.font: rgbFont]).width
        return max(hex, rgb).rounded(.up)
    }()

    /// Per-pixel grid, one physical pixel wide and centered on a physical pixel
    /// so it renders hard instead of as a two-pixel blur. A dark line under a
    /// faint light one keeps it visible on bright and dark content alike.
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
        NSColor.black.withAlphaComponent(0.22).setStroke()
        grid.stroke()
        NSColor.white.withAlphaComponent(0.07).setStroke()
        grid.stroke()
    }

    /// Crosshair arms that stop short of the sampled pixel, plus a ring around
    /// that pixel: dark outline under a light core, so it reads everywhere.
    private func drawCrosshair(in rect: CGRect, pixelPoints: CGFloat) {
        let half = CGFloat(ColorPickerSpec.samplePixels / 2)
        let cell = CGRect(
            x: rect.minX + half * pixelPoints,
            y: rect.minY + half * pixelPoints,
            width: pixelPoints,
            height: pixelPoints
        )
        let arms = NSBezierPath()
        arms.move(to: CGPoint(x: rect.minX, y: cell.midY))
        arms.line(to: CGPoint(x: cell.minX - 2, y: cell.midY))
        arms.move(to: CGPoint(x: cell.maxX + 2, y: cell.midY))
        arms.line(to: CGPoint(x: rect.maxX, y: cell.midY))
        arms.move(to: CGPoint(x: cell.midX, y: rect.minY))
        arms.line(to: CGPoint(x: cell.midX, y: cell.minY - 2))
        arms.move(to: CGPoint(x: cell.midX, y: cell.maxY + 2))
        arms.line(to: CGPoint(x: cell.midX, y: rect.maxY))
        let ring = NSBezierPath(rect: cell.insetBy(dx: -1, dy: -1))
        for path in [arms, ring] {
            path.lineWidth = 3
            NSColor.black.withAlphaComponent(0.8).setStroke()
            path.stroke()
            path.lineWidth = 1
            NSColor.white.setStroke()
            path.stroke()
        }
    }

    /// Swatch (rounded, bordered, lifted by a soft shadow) beside the HEX and a
    /// secondary `rgb(r, g, b)` line.
    private func drawReadout(origin: CGPoint, swatchSide: CGFloat) {
        let swatchRect = CGRect(x: origin.x, y: origin.y, width: swatchSide, height: swatchSide)
        let swatch = NSBezierPath(roundedRect: swatchRect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.set()
        color.setFill()
        swatch.fill()
        NSGraphicsContext.restoreGraphicsState()
        let swatchBorder = NSBezierPath(
            roundedRect: swatchRect.insetBy(dx: 0.25, dy: 0.25),
            xRadius: 8,
            yRadius: 8
        )
        swatchBorder.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.5).setStroke()
        swatchBorder.stroke()

        let hexFont = Self.hexFont
        let rgbFont = Self.rgbFont
        let textX = swatchRect.maxX + Self.textGap
        // NSFont has no lineHeight on AppKit; ascender − descender is close enough.
        let hexHeight = hexFont.ascender - hexFont.descender
        let rgbHeight = rgbFont.ascender - rgbFont.descender
        let lineGap: CGFloat = 1
        let blockY = swatchRect.midY - (hexHeight + lineGap + rgbHeight) / 2
        (rgbText as NSString).draw(
            at: CGPoint(x: textX, y: blockY),
            withAttributes: [.font: rgbFont, .foregroundColor: NSColor.white.withAlphaComponent(0.6)]
        )
        (hex as NSString).draw(
            at: CGPoint(x: textX, y: blockY + rgbHeight + lineGap),
            withAttributes: [.font: hexFont, .foregroundColor: NSColor.white]
        )
    }

    /// `rgb(r, g, b)` of the sampled color. The session builds it from exact
    /// 8-bit sRGB values, so rounding the components recovers them exactly.
    private var rgbText: String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "" }
        func byte(_ component: CGFloat) -> Int { Int((component * 255).rounded()) }
        return "rgb(\(byte(srgb.redComponent)), \(byte(srgb.greenComponent)), \(byte(srgb.blueComponent)))"
    }

    /// Bottom-center hint. The lens follows the cursor, so a fixed hint never
    /// fights the magnifier for space.
    private func drawHint() {
        let text = "click to copy · esc" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
        let textSize = text.size(withAttributes: attributes)
        let symbolSide: CGFloat = 15
        let gap: CGFloat = 7
        let padding: CGFloat = 14
        let pillHeight = max(textSize.height + 14, 30)
        let contentWidth = symbolSide + gap + textSize.width
        let pill = CGRect(
            x: (bounds.width - (contentWidth + padding * 2)) / 2,
            y: bounds.minY + 40,
            width: contentWidth + padding * 2,
            height: pillHeight
        )

        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        border.lineWidth = 0.5
        border.stroke()

        if let symbol = RegionSelectionView.tintedSymbol("eyedropper", side: symbolSide) {
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
}
