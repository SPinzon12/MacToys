import Testing
@testable import MacToys

/// When a finished Text Extractor OCR may still write the clipboard.
struct ExtractionGateTests {
    private let ticket = ExtractionTicket(id: 3, changeCount: 41)

    @Test func latestExtractionWithUntouchedClipboardDelivers() {
        #expect(ticket.verdict(latestID: 3, currentChangeCount: 41) == .deliver)
    }

    @Test func supersededExtractionIsDroppedSilently() {
        // A newer extraction owns the clipboard and the toasts now.
        #expect(ticket.verdict(latestID: 4, currentChangeCount: 41) == .superseded)
        #expect(ticket.verdict(latestID: 4, currentChangeCount: 99) == .superseded)
    }

    @Test func clipboardChangedMeanwhileIsNotOverwritten() {
        // The user copied something else while OCR ran: keep their copy.
        #expect(ticket.verdict(latestID: 3, currentChangeCount: 42) == .clipboardChanged)
    }
}

/// What a finished extraction does with its OCR result, per verdict.
struct ExtractionOutcomeTests {
    private let messages = (confirmation: "Copied 5 chars", miss: "No text found")

    private func outcome(_ verdict: ExtractionTicket.Verdict, _ text: String?) -> ExtractionOutcome {
        ExtractionOutcome.decide(verdict: verdict, text: text, confirmation: messages.confirmation, missMessage: messages.miss)
    }

    @Test func deliverCopiesTextWithConfirmation() {
        #expect(outcome(.deliver, "hello") == .copy("hello", toast: "Copied 5 chars"))
    }

    @Test func deliverWithNothingRecognizedShowsMiss() {
        #expect(outcome(.deliver, nil) == .miss("No text found"))
    }

    @Test func supersededDoesNothingEvenWhenEmpty() {
        #expect(outcome(.superseded, "hello") == .nothing)
        #expect(outcome(.superseded, nil) == .nothing)
    }

    @Test func clipboardChangedKeepsUserCopy() {
        #expect(outcome(.clipboardChanged, "hello") == .keptNewerCopy)
    }

    @Test func clipboardChangedWithNothingRecognizedShowsMissInstead() {
        // "Kept your newer copy" would be misleading when there was nothing to write.
        #expect(outcome(.clipboardChanged, nil) == .miss("No text found"))
    }
}
