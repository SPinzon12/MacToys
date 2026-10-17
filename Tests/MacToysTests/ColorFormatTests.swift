import Testing
@testable import MacToys

/// Copy formats offered by the Color Picker.
struct ColorFormatTests {
    @Test func hex() {
        #expect(ColorFormat.hex.string(r: 30, g: 144, b: 255) == "#1E90FF")
        #expect(ColorFormat.hex.string(r: 0, g: 0, b: 0) == "#000000")
    }

    @Test func rgb() {
        #expect(ColorFormat.rgb.string(r: 30, g: 144, b: 255) == "rgb(30, 144, 255)")
    }

    @Test func hslMatchesCSSRounding() {
        // dodgerblue is hsl(210, 100%, 56%) in CSS.
        #expect(ColorFormat.hsl.string(r: 30, g: 144, b: 255) == "hsl(210, 100%, 56%)")
        #expect(ColorFormat.hsl.string(r: 255, g: 255, b: 255) == "hsl(0, 0%, 100%)")
        #expect(ColorFormat.hsl.string(r: 0, g: 0, b: 0) == "hsl(0, 0%, 0%)")
        #expect(ColorFormat.hsl.string(r: 255, g: 0, b: 0) == "hsl(0, 100%, 50%)")
        #expect(ColorFormat.hsl.string(r: 128, g: 128, b: 128) == "hsl(0, 0%, 50%)")
    }

    @Test func cyclesInBothDirections() {
        #expect(ColorFormat.hex.next == .rgb)
        #expect(ColorFormat.rgb.next == .hsl)
        #expect(ColorFormat.hsl.next == .hex)
        #expect(ColorFormat.hex.previous == .hsl)
    }

    @Test func titles() {
        #expect(ColorFormat.allCases.map(\.title) == ["HEX", "RGB", "HSL"])
    }

    @Test func readableTextOnSwatch() {
        // Light colors get dark text and vice versa (relative luminance).
        #expect(ColorFormat.prefersDarkText(r: 255, g: 255, b: 255))
        #expect(ColorFormat.prefersDarkText(r: 255, g: 210, b: 60))
        #expect(!ColorFormat.prefersDarkText(r: 0, g: 0, b: 0))
        #expect(!ColorFormat.prefersDarkText(r: 30, g: 60, b: 200))
    }
}
