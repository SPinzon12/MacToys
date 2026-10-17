/// Color Picker — ⌃⇧C / menu → magnifier-lens overlay; click copies HEX.
enum ColorPickerModule {
    static func trigger() {
        // Carbon hotkey callbacks are not main-actor isolated; hop before AppKit.
        Task { @MainActor in
            if let active = ColorPickerSession.current {
                active.finish() // re-trigger while active cancels; never stacks
            } else {
                ColorPickerSession.start()
            }
        }
    }
}
