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

/// What a finished extraction does with its OCR result. Pure, so the routing
/// is unit-tested; the session only performs it.
enum ExtractionOutcome: Equatable {
    /// Superseded: the newer extraction owns the clipboard and the toasts.
    case nothing
    /// Nothing recognized: say so (also replaces a lingering waiting toast).
    case miss(String)
    /// The user copied something else meanwhile; keep it and say so.
    case keptNewerCopy
    case copy(String, toast: String)

    static func decide(
        verdict: ExtractionTicket.Verdict,
        text: String?,
        confirmation: String,
        missMessage: String
    ) -> ExtractionOutcome {
        guard verdict != .superseded else { return .nothing }
        // An empty result has nothing to write, so "kept your copy" would mislead.
        guard let text else { return .miss(missMessage) }
        return verdict == .deliver ? .copy(text, toast: confirmation) : .keptNewerCopy
    }
}
