// Renders the app icon into an .iconset folder; `iconutil` turns it into .icns.
//
//   swift scripts/make-icon.swift <out.iconset>
//
// The glyph is drawn with plain paths on purpose: the SF Symbols license does
// not allow symbols in app icons, so the menu-bar symbol cannot be reused here.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Four-point sparkle centered on `c`: long arms of length `r`, concave sides.
func sparkle(_ c: CGPoint, _ r: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let pinch = r * 0.18
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.curve(to: CGPoint(x: c.x + r, y: c.y), controlPoint1: CGPoint(x: c.x + pinch, y: c.y + pinch), controlPoint2: CGPoint(x: c.x + pinch, y: c.y + pinch))
    path.curve(to: CGPoint(x: c.x, y: c.y - r), controlPoint1: CGPoint(x: c.x + pinch, y: c.y - pinch), controlPoint2: CGPoint(x: c.x + pinch, y: c.y - pinch))
    path.curve(to: CGPoint(x: c.x - r, y: c.y), controlPoint1: CGPoint(x: c.x - pinch, y: c.y - pinch), controlPoint2: CGPoint(x: c.x - pinch, y: c.y - pinch))
    path.curve(to: CGPoint(x: c.x, y: c.y + r), controlPoint1: CGPoint(x: c.x - pinch, y: c.y + pinch), controlPoint2: CGPoint(x: c.x - pinch, y: c.y + pinch))
    path.close()
    return path
}

/// The master artwork on a 1024 canvas (macOS grid: 824 pt squircle, 100 pt margin).
func drawIcon(in size: CGFloat) {
    let s = size / 1024
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    // Soft drop shadow under the tile, as system icons have.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Indigo → violet tile with a lit top edge.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(
        starting: NSColor(srgbRed: 0.36, green: 0.42, blue: 1.00, alpha: 1),
        ending: NSColor(srgbRed: 0.62, green: 0.25, blue: 0.93, alpha: 1)
    )?.draw(in: tile, angle: -60)
    NSGradient(
        starting: NSColor.white.withAlphaComponent(0.28),
        ending: NSColor.white.withAlphaComponent(0)
    )?.draw(in: CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Wand: a rounded bar from lower-left to upper-right, white tip.
    NSGraphicsContext.saveGraphicsState()
    let wandShadow = NSShadow()
    wandShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    wandShadow.shadowBlurRadius = 14 * s
    wandShadow.shadowOffset = NSSize(width: 0, height: -6 * s)
    wandShadow.set()
    let transform = NSAffineTransform()
    transform.translateX(by: 470 * s, yBy: 470 * s)
    transform.rotate(byDegrees: 45)
    let bar = NSBezierPath(roundedRect: CGRect(x: -290 * s, y: -38 * s, width: 580 * s, height: 76 * s), xRadius: 38 * s, yRadius: 38 * s)
    bar.transform(using: transform as AffineTransform)
    NSColor(white: 1, alpha: 0.92).setFill()
    bar.fill()
    let tip = NSBezierPath(roundedRect: CGRect(x: 150 * s, y: -38 * s, width: 140 * s, height: 76 * s), xRadius: 38 * s, yRadius: 38 * s)
    tip.transform(using: transform as AffineTransform)
    NSColor(srgbRed: 1.0, green: 0.86, blue: 0.40, alpha: 1).setFill()
    tip.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Sparkles around the tip.
    NSColor.white.setFill()
    sparkle(CGPoint(x: 735 * s, y: 760 * s), 92 * s).fill()
    sparkle(CGPoint(x: 560 * s, y: 800 * s), 46 * s).fill()
    sparkle(CGPoint(x: 790 * s, y: 585 * s), 40 * s).fill()
}

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024)
]
for (name, pixels) in sizes {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate \(pixels) px bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: outDir.appendingPathComponent("icon_\(name).png"))
}
print("wrote \(sizes.count) images to \(outDir.path)")
