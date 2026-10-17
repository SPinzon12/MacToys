import AppKit

/// One picked color in 8-bit sRGB — what every format and the history store.
struct PickedColor: Equatable, Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From the system sampler's color, converted to sRGB (what HEX/RGB/HSL mean).
    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(max(component, 0), 1) * 255).rounded()) }
        self.init(r: byte(srgb.redComponent), g: byte(srgb.greenComponent), b: byte(srgb.blueComponent))
    }

    /// "#RRGGBB"; anything else is rejected.
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
    }

    func string(in format: ColorFormat) -> String { format.string(r: r, g: g, b: b) }

    /// Dark text reads better on this color than white does (WCAG contrast:
    /// black wins when relative luminance is above ~0.179).
    var prefersDarkText: Bool {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

/// The last picked colors, newest first, for the card's "Recent" row.
struct ColorHistory {
    static let limit = 10

    private(set) var colors: [PickedColor] = []

    init() {}

    /// Restores from stored "#RRGGBB" strings, skipping anything unreadable.
    init(hexList: [String]) {
        colors = Array(hexList.compactMap(PickedColor.init(hex:)).prefix(Self.limit))
    }

    /// Picking a color again moves it to the front instead of duplicating it.
    mutating func record(_ color: PickedColor) {
        colors.removeAll { $0 == color }
        colors.insert(color, at: 0)
        if colors.count > Self.limit { colors.removeLast(colors.count - Self.limit) }
    }

    var hexList: [String] { colors.map { $0.string(in: .hex) } }

    // MARK: - Persistence

    private static let defaultsKey = "colorPicker.history"

    static func load() -> ColorHistory {
        ColorHistory(hexList: UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func save() {
        UserDefaults.standard.set(hexList, forKey: Self.defaultsKey)
    }
}
