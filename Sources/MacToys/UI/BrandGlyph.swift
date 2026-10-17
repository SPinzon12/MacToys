import AppKit

/// The MacToys mark for the menu bar: the app icon's three stacked toy blocks
/// as a template image, so macOS tints it for light, dark and highlighted bars.
enum BrandGlyph {
    static func menuBar(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let unit = rect.width / 18
            let side = 7.2 * unit, gap = 1.2 * unit, radius = 1.8 * unit
            let left = CGRect(x: rect.midX - side - gap / 2, y: 1.2 * unit, width: side, height: side)
            let right = CGRect(x: rect.midX + gap / 2, y: 1.2 * unit, width: side, height: side)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: left, xRadius: radius, yRadius: radius).fill()
            NSBezierPath(roundedRect: right, xRadius: radius, yRadius: radius).fill()
            // The top block sits slightly askew, like the app icon's.
            let top = CGRect(x: rect.midX - side / 2, y: left.maxY + gap, width: side, height: side)
            let tilt = NSAffineTransform()
            tilt.translateX(by: top.midX, yBy: top.midY)
            tilt.rotate(byDegrees: -7)
            tilt.translateX(by: -top.midX, yBy: -top.midY)
            let path = NSBezierPath(roundedRect: top, xRadius: radius, yRadius: radius)
            path.transform(using: tilt as AffineTransform)
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacToys"
        return image
    }
}
