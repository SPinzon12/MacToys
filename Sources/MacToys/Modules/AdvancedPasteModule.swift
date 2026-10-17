/// Advanced Paste — ⌃⇧V / menu → transform menu for the current clipboard;
/// the chosen transform runs, then a synthetic ⌘V pastes the result.
enum AdvancedPasteModule {
    static func trigger() {
        // Carbon hotkey callbacks are not main-actor isolated; hop before AppKit.
        Task { @MainActor in
            await PasteCoordinator.shared.showMenu()
        }
    }
}
