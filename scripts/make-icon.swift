// Renders the app icon into an .iconset folder; `iconutil` turns it into .icns.
//
//   swift scripts/make-icon.swift <out.iconset>
//
// Drawn with plain paths on purpose: the SF Symbols license does not allow
// symbols in app icons. The menu-bar glyph (UI/BrandGlyph.swift) is the same
// three blocks as a monochrome template.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Toy blocks — three rounded shape-sorter blocks stacked by hand on the
/// indigo-to-violet tile.
enum Blocks {
    static let mint = NSColor(srgbRed: 0.24, green: 0.84, blue: 0.70, alpha: 1)
    static let coral = NSColor(srgbRed: 1.00, green: 0.42, blue: 0.42, alpha: 1)
    static let sun = NSColor(srgbRed: 1.00, green: 0.79, blue: 0.29, alpha: 1)

    /// One toy block: rounded face, lit top, darker lip at the bottom, soft shadow.
    static func block(_ rect: CGRect, color: NSColor, radius: CGFloat, s: CGFloat, emboss: (CGRect) -> NSBezierPath) {
        let face = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 22 * s
        shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
        shadow.set()
        color.blended(withFraction: 0.25, of: .black)!.setFill()
        face.fill() // the lip, seen under the face
        NSGraphicsContext.restoreGraphicsState()

        let top = rect.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: 0)
        let raised = CGRect(x: top.minX, y: top.minY + 16 * s, width: top.width, height: top.height - 16 * s)
        let raisedFace = NSBezierPath(roundedRect: raised, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        raisedFace.addClip()
        NSGradient(starting: color.blended(withFraction: 0.22, of: .white)!, ending: color)?
            .draw(in: raised, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Shape-sorter emboss: a lighter inset shape with a hint of depth.
        let shape = emboss(raised.insetBy(dx: raised.width * 0.27, dy: raised.height * 0.27))
        NSGraphicsContext.saveGraphicsState()
        let inner = NSShadow()
        inner.shadowColor = color.blended(withFraction: 0.35, of: .black)!.withAlphaComponent(0.6)
        inner.shadowBlurRadius = 2 * s
        inner.shadowOffset = NSSize(width: 0, height: -4 * s)
        inner.set()
        NSColor.white.withAlphaComponent(0.55).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func circle(_ r: CGRect) -> NSBezierPath { NSBezierPath(ovalIn: r) }

    static func triangle(_ r: CGRect) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.line(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.08))
        p.line(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.08))
        p.close()
        p.lineJoinStyle = .round
        return p
    }

    static func star(_ r: CGRect) -> NSBezierPath {
        let p = NSBezierPath()
        let c = CGPoint(x: r.midX, y: r.midY - r.height * 0.02)
        let outer = r.width / 2, inner = outer * 0.45
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 + .pi / 2
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            i == 0 ? p.move(to: point) : p.line(to: point)
        }
        p.close()
        return p
    }

    /// The full app icon on a 1024 canvas scaled to `size`.
    static func drawIcon(in size: CGFloat) {
        let s = size / 1024
        let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let squircle = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowBlurRadius = 24 * s
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.set()
        NSColor.black.setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        NSGradient(
            starting: NSColor(srgbRed: 0.38, green: 0.44, blue: 1.00, alpha: 1),
            ending: NSColor(srgbRed: 0.58, green: 0.26, blue: 0.92, alpha: 1)
        )?.draw(in: tile, angle: -60)
        NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))?
            .draw(in: CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

        let side = 268 * s, gap = 26 * s, radius = 54 * s
        let left = CGRect(x: 512 * s - side - gap / 2, y: 218 * s, width: side, height: side)
        let right = CGRect(x: 512 * s + gap / 2, y: 218 * s, width: side, height: side)
        block(left, color: mint, radius: radius, s: s, emboss: circle)
        block(right, color: coral, radius: radius, s: s, emboss: triangle)

        // The top block sits slightly askew: stacked by hand, not by a machine.
        let topRect = CGRect(x: 512 * s - side / 2, y: left.maxY + gap - 6 * s, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: topRect.midX, yBy: topRect.midY)
        transform.rotate(byDegrees: -7)
        transform.translateX(by: -topRect.midX, yBy: -topRect.midY)
        transform.concat()
        block(topRect, color: sun, radius: radius, s: s, emboss: star)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func drawIcon(in size: CGFloat) { Blocks.drawIcon(in: size) }

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
