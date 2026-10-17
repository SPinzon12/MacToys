import Foundation

/// The ordered history, newest first. Pure value type: the service owns the
/// pasteboard polling and disk I/O around it.
struct ClipboardHistory: Codable {
    static let defaultLimit = 200

    private(set) var entries: [ClipboardEntry] = []
    var limit: Int

    init(limit: Int = Self.defaultLimit) {
        self.limit = limit
    }

    struct RecordOutcome {
        /// False when identical content was already there and got promoted.
        let inserted: Bool
        /// Pushed past the cap; the caller deletes their image files.
        let evicted: [ClipboardEntry]
    }

    /// Identical content keeps its original entry (and image file) and moves
    /// to the top with the new date and source app.
    @discardableResult
    mutating func record(_ entry: ClipboardEntry) -> RecordOutcome {
        if let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            var existing = entries.remove(at: index)
            existing.date = entry.date
            existing.sourceApp = entry.sourceApp
            existing.sourceBundleID = entry.sourceBundleID
            entries.insert(existing, at: 0)
            return RecordOutcome(inserted: false, evicted: [])
        }
        entries.insert(entry, at: 0)
        let evicted = entries.count > limit ? Array(entries[limit...]) : []
        entries.removeLast(evicted.count)
        return RecordOutcome(inserted: true, evicted: evicted)
    }

    mutating func promote(_ id: UUID, date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.date = date
        entries.insert(entry, at: 0)
    }

    mutating func removeAll() -> [ClipboardEntry] {
        defer { entries.removeAll() }
        return entries
    }

    /// Every whitespace-separated token must appear, case- and
    /// diacritic-insensitive ("cafe" finds "Café").
    func filtered(_ query: String) -> [ClipboardEntry] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return entries }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.filter { entry in
            let haystack = entry.searchableText
            return tokens.allSatisfy { haystack.range(of: $0, options: options) != nil }
        }
    }

    // MARK: - Day sections

    enum Section: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case earlier = "Earlier"
    }

    static func section(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> Section {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .earlier
    }
}
