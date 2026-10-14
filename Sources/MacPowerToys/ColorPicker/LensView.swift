import AppKit
import Carbon

/// The overlay's content view: draws the magnifier lens (magnified pixels,
/// crosshair, color swatch, HEX readout) and routes input back to the session.
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
        let pad: CGFloat = 6
        let gap: CGFloat = 8
        let swatchSide: CGFloat = 24
        let lensWidth = imageSize + pad * 2
        let lensHeight = pad + imageSize + gap + swatchSide + pad

        // Anchor up-right of the cursor; flip to the other side at the desktop
        // edge, then clamp so the lens never leaves the (multi-display) bounds.
        var origin = CGPoint(x: cursor.x + 12, y: cursor.y + 12)
        if origin.x + lensWidth > bounds.maxX {
            origin.x = cursor.x - 12 - lensWidth
        }
        if origin.y + lensHeight > bounds.maxY {
            origin.y = cursor.y - 12 - lensHeight
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - lensWidth)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - lensHeight)

        let lensRect = CGRect(x: origin.x, y: origin.y, width: lensWidth, height: lensHeight)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: lensRect, xRadius: 8, yRadius: 8).fill()

        let imageRect = CGRect(
            x: origin.x + pad,
            y: origin.y + lensHeight - pad - imageSize,
            width: imageSize,
            height: imageSize
        )
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Nearest-neighbor: the lens must show hard pixel edges, not smoothing.
        context.interpolationQuality = .none
        context.draw(lensImage, in: imageRect)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        NSBezierPath(rect: imageRect).stroke()

        // Crosshair centered on the sampled pixel: dark outline under a light
        // core, so it reads on both dark and bright lens content.
        let center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        let horizontal = NSBezierPath()
        horizontal.move(to: CGPoint(x: imageRect.minX, y: center.y))
        horizontal.line(to: CGPoint(x: imageRect.maxX, y: center.y))
        let vertical = NSBezierPath()
        vertical.move(to: CGPoint(x: center.x, y: imageRect.minY))
        vertical.line(to: CGPoint(x: center.x, y: imageRect.maxY))
        for path in [horizontal, vertical] {
            path.lineWidth = 3
            NSColor.black.withAlphaComponent(0.85).setStroke()
            path.stroke()
            path.lineWidth = 1
            NSColor.white.setStroke()
            path.stroke()
        }

        // Swatch + HEX readout under the lens image.
        let rowY = origin.y + pad
        let swatchRect = CGRect(x: origin.x + pad, y: rowY, width: swatchSide, height: swatchSide)
        color.setFill()
        NSBezierPath(rect: swatchRect).fill()
        NSColor.white.withAlphaComponent(0.4).setStroke()
        NSBezierPath(rect: swatchRect).stroke()

        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        // NSFont has no lineHeight on AppKit; ascender − descender is close enough to center.
        let textHeight = font.ascender - font.descender
        let textY = rowY + (swatchSide - textHeight) / 2
        (hex as NSString).draw(
            at: CGPoint(x: swatchRect.maxX + 8, y: textY),
            withAttributes: attributes
        )
    }
}
