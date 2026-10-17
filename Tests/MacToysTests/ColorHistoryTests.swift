import Testing
@testable import MacToys

/// Recent colors and nearest color names for the Color Picker card.
struct ColorHistoryTests {
    private let blue = PickedColor(r: 30, g: 144, b: 255)
    private let red = PickedColor(r: 255, g: 0, b: 0)

    @Test func newestFirst() {
        var history = ColorHistory()
        history.record(red)
        history.record(blue)
        #expect(history.colors == [blue, red])
    }

    @Test func pickingAgainMovesToFrontWithoutDuplicates() {
        var history = ColorHistory()
        history.record(red)
        history.record(blue)
        history.record(red)
        #expect(history.colors == [red, blue])
    }

    @Test func keepsTheLastTen() {
        var history = ColorHistory()
        for value in 0..<12 {
            history.record(PickedColor(r: UInt8(value), g: 0, b: 0))
        }
        #expect(history.colors.count == ColorHistory.limit)
        #expect(history.colors.first == PickedColor(r: 11, g: 0, b: 0))
        #expect(history.colors.last == PickedColor(r: 2, g: 0, b: 0))
    }

    @Test func storesAsHexStrings() {
        var history = ColorHistory()
        history.record(blue)
        history.record(red)
        #expect(history.hexList == ["#FF0000", "#1E90FF"])
        #expect(ColorHistory(hexList: ["#FF0000", "#1E90FF", "nonsense"]).colors == [red, blue])
    }

    @Test func exactCSSNames() {
        #expect(ColorNames.nearest(to: blue) == "Dodger Blue")
        #expect(ColorNames.nearest(to: red) == "Red")
        #expect(ColorNames.nearest(to: PickedColor(r: 255, g: 255, b: 255)) == "White")
    }

    @Test func nearestNameForInBetweenColors() {
        // One step off dodgerblue is still Dodger Blue.
        #expect(ColorNames.nearest(to: PickedColor(r: 31, g: 145, b: 254)) == "Dodger Blue")
        #expect(ColorNames.nearest(to: PickedColor(r: 2, g: 1, b: 3)) == "Black")
    }

    @Test func formatsReadFromThePickedColor() {
        #expect(blue.string(in: .hex) == "#1E90FF")
        #expect(blue.string(in: .rgb) == "rgb(30, 144, 255)")
        #expect(blue.string(in: .hsl) == "hsl(210, 100%, 56%)")
    }

    @Test func readableTextOnTheColorItself() {
        // PowerToys-style chip: the chip is the color, so the code switches between
        // dark and light text by relative luminance.
        #expect(PickedColor(r: 255, g: 255, b: 255).prefersDarkText)
        #expect(PickedColor(r: 255, g: 210, b: 60).prefersDarkText)   // yellow
        #expect(PickedColor(r: 46, g: 204, b: 113).prefersDarkText)   // light green
        #expect(!PickedColor(r: 0, g: 0, b: 0).prefersDarkText)
        #expect(!PickedColor(r: 30, g: 60, b: 200).prefersDarkText)   // deep blue
        #expect(!PickedColor(r: 40, g: 44, b: 52).prefersDarkText)    // editor dark gray
    }
}

