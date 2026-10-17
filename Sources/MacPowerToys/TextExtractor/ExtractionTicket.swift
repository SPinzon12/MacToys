/// Taken when an extraction starts; checked when its OCR finishes, which can
/// be ~26 s later on a cold Vision model. Only the newest extraction may write,
/// and only while nobody else has touched the clipboard since it started.
struct ExtractionTicket: Equatable {
    let id: Int
    /// `NSPasteboard.general.changeCount` when the extraction started.
    let changeCount: Int

    enum Verdict: Equatable {
        case deliver
        /// A newer extraction started; it owns the clipboard and the toasts.
        case superseded
        /// The user copied something else meanwhile; keep their copy.
        case clipboardChanged
    }

    func verdict(latestID: Int, currentChangeCount: Int) -> Verdict {
        guard id == latestID else { return .superseded }
        guard changeCount == currentChangeCount else { return .clipboardChanged }
        return .deliver
    }
}
