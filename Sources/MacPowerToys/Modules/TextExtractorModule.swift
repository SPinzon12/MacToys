/// Text Extractor — ⌃⇧O / menu → dimmed screen overlay; drag OCRs the region,
/// a plain click copies the word under the cursor.
enum TextExtractorModule {
    static func trigger() {
        // Carbon hotkey callbacks are not main-actor isolated; hop before AppKit.
        Task { @MainActor in
            if let active = TextExtractorSession.current {
                active.finish() // re-trigger while active cancels; never stacks
            } else {
                TextExtractorSession.start()
            }
        }
    }
}
