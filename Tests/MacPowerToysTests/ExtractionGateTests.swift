import Testing
@testable import MacPowerToys

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
