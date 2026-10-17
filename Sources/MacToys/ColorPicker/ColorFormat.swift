import Foundation

/// What the Color Picker copies. Cycled with ⇥ / ← → in the lens and remembered.
enum ColorFormat: String, CaseIterable {
    case hex
    case rgb
    case hsl

    var title: String { rawValue.uppercased() }

    func string(r: UInt8, g: UInt8, b: UInt8) -> String {
        switch self {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = Self.hsl(r: r, g: g, b: b)
            return "hsl(\(h), \(s)%, \(l)%)"
        }
    }

    var next: ColorFormat { Self.allCases[(index + 1) % Self.allCases.count] }
    var previous: ColorFormat { Self.allCases[(index + Self.allCases.count - 1) % Self.allCases.count] }

    private var index: Int { Self.allCases.firstIndex(of: self)! }

    /// Hue in degrees, saturation and lightness in percent, rounded like CSS tools.
    static func hsl(r: UInt8, g: UInt8, b: UInt8) -> (Int, Int, Int) {
        let red = Double(r) / 255, green = Double(g) / 255, blue = Double(b) / 255
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxC {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded()))
    }

    /// Dark text reads better on this color (WCAG relative luminance > 0.4).
    static func prefersDarkText(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.4
    }

    // MARK: - Remembered choice

    private static let defaultsKey = "colorPicker.format"

    static var saved: ColorFormat {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(ColorFormat.init) ?? .hex }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
