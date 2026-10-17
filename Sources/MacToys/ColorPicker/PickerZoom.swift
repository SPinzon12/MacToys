import Foundation

/// The Color Picker's magnifier, PowerToys-style: off by default (just the color
/// chip next to the cursor); the scroll wheel turns it on and steps the zoom.
struct PickerZoom {
    /// Physical screen pixels per captured pixel at each wheel step.
    static let levels = [4, 6, 8, 12, 16]

    /// nil = magnifier hidden.
    private(set) var factor: Int?

    mutating func step(by delta: Int) {
        let current = factor.flatMap { Self.levels.firstIndex(of: $0) } ?? -1
        let next = min(max(current + delta, -1), Self.levels.count - 1)
        factor = next < 0 ? nil : Self.levels[next]
    }

    /// Captured pixels per side so the loupe is filled at `factor`. Odd, so the
    /// pixel under the cursor sits exactly in the middle.
    static func capturePixels(loupePoints: Double, scale: Double, factor: Int) -> Int {
        let pixels = Int((loupePoints * scale / Double(factor)).rounded(.up))
        return pixels.isMultiple(of: 2) ? pixels + 1 : pixels
    }
}
