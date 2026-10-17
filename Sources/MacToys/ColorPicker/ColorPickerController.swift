import AppKit

/// Color Picker flow: the system's own loupe (`NSColorSampler`, the one every
/// macOS color panel uses) picks the color; MacToys copies it in the saved
/// format and shows the result card with all formats and recent colors.
///
/// The system samples the screen itself, so this module needs no Screen
/// Recording permission (that is what NSColorSampler was introduced for).
@MainActor
final class ColorPickerController {
    static let shared = ColorPickerController()

    private var sampling = false
    /// Held for the session: the sampler is documented to keep itself alive, but
    /// if it were ever freed without calling back, `sampling` would stick and the
    /// hotkey would stop working.
    private var sampler: NSColorSampler?
    private var history = ColorHistory.load()

    private init() {}

    func pick() {
        // The system loupe is already up: it owns Esc and the click.
        guard !sampling else { return }
        sampling = true
        // Gone at once, not faded: the loupe must not sample the old card.
        ColorResultPanelController.shared.close(animated: false)
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { selected in
            // Documented to run on the main thread.
            MainActor.assumeIsolated {
                ColorPickerController.shared.finishSampling(selected)
            }
        }
    }

    private func finishSampling(_ selected: NSColor?) {
        sampling = false
        sampler = nil
        guard let selected, let color = PickedColor(selected) else { return } // cancelled
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
