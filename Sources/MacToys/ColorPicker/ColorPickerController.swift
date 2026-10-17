import AppKit

/// Color Picker flow, PowerToys-style: a chip with the color and its code
/// follows the cursor (the scroll wheel adds a magnifier); a click copies the
/// color in the saved format and shows the result card with all formats and
/// recent colors. Pressing the hotkey again while picking cancels.
@MainActor
final class ColorPickerController {
    static let shared = ColorPickerController()

    private var session: ColorPickerSession?
    private var history = ColorHistory.load()

    private init() {}

    func pick() {
        if let session { // re-trigger while picking cancels; sessions never stack
            session.finish()
            return
        }
        // Gone at once, not faded: the next capture must not see the old card.
        ColorResultPanelController.shared.close(animated: false)
        let session = ColorPickerSession(
            onPicked: { color in ColorPickerController.shared.picked(color) },
            onEnded: { ColorPickerController.shared.session = nil }
        )
        self.session = session
        session.begin()
    }

    private func picked(_ color: PickedColor) {
        let format = ColorFormat.saved
        Self.copy(color.string(in: format))
        history.record(color)
        history.save()
        ColorResultPanelController.shared.show(
            color: color,
            copiedFormat: format,
            history: history.colors,
            onPickAgain: { ColorPickerController.shared.pick() },
            onRecent: { recent in ColorPickerController.shared.reuse(recent) }
        )
    }

    /// Clicking a recent swatch makes it the current color again.
    private func reuse(_ color: PickedColor) {
        history.record(color)
        history.save()
        Self.copy(color.string(in: ColorFormat.saved))
        ColorResultPanelController.shared.update(color: color, copiedFormat: ColorFormat.saved, history: history.colors)
    }

    static func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(value, forType: .string)
    }
}
