import Testing
@testable import MacToys

/// The Color Picker's scroll-wheel zoom, PowerToys-style: off until you scroll.
struct PickerZoomTests {
    @Test func startsOffAndStepsUpWithTheWheel() {
        var zoom = PickerZoom()
        #expect(zoom.factor == nil)
        zoom.step(by: 1)
        #expect(zoom.factor == 4)
        zoom.step(by: 1)
        zoom.step(by: 1)
        #expect(zoom.factor == 8)
    }

    @Test func clampsAtBothEnds() {
        var zoom = PickerZoom()
        for _ in 0..<20 { zoom.step(by: 1) }
        #expect(zoom.factor == 16)
        for _ in 0..<20 { zoom.step(by: -1) }
        #expect(zoom.factor == nil) // scrolled all the way back: magnifier gone
    }

    @Test func capturedPixelsCoverTheLoupeAndStayOdd() {
        // 132 pt loupe on a 2× display = 264 device pixels.
        #expect(PickerZoom.capturePixels(loupePoints: 132, scale: 2, factor: 4) == 67)
        #expect(PickerZoom.capturePixels(loupePoints: 132, scale: 2, factor: 8) == 33)
        #expect(PickerZoom.capturePixels(loupePoints: 132, scale: 2, factor: 16) == 17)
        #expect(PickerZoom.capturePixels(loupePoints: 132, scale: 1, factor: 12) == 11)
        for factor in PickerZoom.levels {
            #expect(PickerZoom.capturePixels(loupePoints: 132, scale: 2, factor: factor) % 2 == 1)
        }
    }
}
