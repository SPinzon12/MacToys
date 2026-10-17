import AppKit

/// The app's glass background for borderless panels.
@MainActor
enum GlassSurface {
    /// Liquid Glass on macOS 26+, behind-window vibrancy before it. Either way
    /// the surface samples what is behind the window instead of faking it.
    static func make(hosting: NSView, size: NSSize, radius: CGFloat) -> NSView {
        hosting.frame = NSRect(origin: .zero, size: size)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = radius
            glass.style = .regular
            glass.contentView = hosting
            return glass
        }
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: radius)
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        return effect
    }

    /// Stretchable rounded-rect mask: the documented way to round a
    /// behind-window `NSVisualEffectView` (layer corner radius does not clip it).
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
