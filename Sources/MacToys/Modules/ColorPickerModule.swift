/// Color Picker — ⌃⇧C / panel → a chip with the color follows the cursor (scroll
/// to magnify); click copies it and opens the result card. ⌃⇧C again cancels.
enum ColorPickerModule {
    static func trigger() {
        // Carbon hotkey callbacks are not main-actor isolated; hop before AppKit.
        Task { @MainActor in
            ColorPickerController.shared.pick()
        }
    }
}
