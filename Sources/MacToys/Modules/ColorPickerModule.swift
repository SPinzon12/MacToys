/// Color Picker — ⌃⇧C / panel → the system color loupe; click copies the color
/// and opens the result card (HEX / RGB / HSL, recent colors).
enum ColorPickerModule {
    static func trigger() {
        // Carbon hotkey callbacks are not main-actor isolated; hop before AppKit.
        Task { @MainActor in
            ColorPickerController.shared.pick()
        }
    }
}
