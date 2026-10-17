import Foundation
import Testing
@testable import MacToys

/// Keep Awake session timing and the menu's remaining-time label.
struct KeepAwakeTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func timedDurationsEndAfterTheirInterval() {
        let cases: [(KeepAwakeDuration, TimeInterval)] = [
            (.minutes15, 15 * 60), (.hour1, 3600), (.hours2, 7200), (.hours4, 14_400)
        ]
        for (duration, interval) in cases {
            let session = KeepAwakeSession(duration: duration, startedAt: start)
            #expect(session.endsAt == start.addingTimeInterval(interval), "\(duration)")
        }
    }

    @Test func indefinitelyNeverEnds() {
        let session = KeepAwakeSession(duration: .indefinitely, startedAt: start)
        #expect(session.endsAt == nil)
        #expect(session.remaining(at: start.addingTimeInterval(1_000_000)) == nil)
        #expect(!session.isExpired(at: start.addingTimeInterval(1_000_000)))
    }

    @Test func expiresExactlyAtTheEnd() {
        let session = KeepAwakeSession(duration: .minutes15, startedAt: start)
        #expect(!session.isExpired(at: start.addingTimeInterval(15 * 60 - 1)))
        #expect(session.isExpired(at: start.addingTimeInterval(15 * 60)))
        // Woken from sleep long after the end: still expired, never negative.
        #expect(session.isExpired(at: start.addingTimeInterval(10 * 3600)))
        #expect(session.remaining(at: start.addingTimeInterval(10 * 3600)) == 0)
    }

    @Test func statusLabels() {
        #expect(KeepAwakeSession.statusLabel(remaining: nil) == "On until you turn it off")
        #expect(KeepAwakeSession.statusLabel(remaining: 42 * 60) == "On — 42 min left")
        #expect(KeepAwakeSession.statusLabel(remaining: 65 * 60) == "On — 1 h 05 min left")
        #expect(KeepAwakeSession.statusLabel(remaining: 2 * 3600) == "On — 2 h 00 min left")
        #expect(KeepAwakeSession.statusLabel(remaining: 30) == "On — less than 1 min left")
    }

    @Test func remainingMinutesRoundUp() {
        // 14 min 1 s left reads as 15 min: the label never promises less than is left.
        #expect(KeepAwakeSession.statusLabel(remaining: 14 * 60 + 1) == "On — 15 min left")
    }

    @Test func durationTitles() {
        #expect(KeepAwakeDuration.allCases.map(\.title) == ["15 Minutes", "1 Hour", "2 Hours", "4 Hours", "Indefinitely"])
    }

    // MARK: - Extending and end-time labels

    private var clock: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    @Test func extendingPushesTheEndBack() {
        var session = KeepAwakeSession(duration: .minutes15, startedAt: start)
        session.extend(by: 15 * 60)
        session.extend(by: 15 * 60)
        #expect(session.endsAt == start.addingTimeInterval(45 * 60))
        #expect(session.remaining(at: start.addingTimeInterval(20 * 60)) == TimeInterval(25 * 60))
    }

    @Test func extendingIndefiniteDoesNothing() {
        var session = KeepAwakeSession(duration: .indefinitely, startedAt: start)
        session.extend(by: 15 * 60)
        #expect(session.endsAt == nil)
        #expect(!session.canExtend)
        #expect(KeepAwakeSession(duration: .hour1, startedAt: start).canExtend)
    }

    @Test func statusLabelWithEndTime() {
        let session = KeepAwakeSession(duration: .hour1, startedAt: start) // 2027-01-15 08:00 UTC
        #expect(session.statusLabel(at: start.addingTimeInterval(18 * 60), clock: clock) == "On — 42 min left · until 09:00")
        let forever = KeepAwakeSession(duration: .indefinitely, startedAt: start)
        #expect(forever.statusLabel(at: start, clock: clock) == "On until you turn it off")
    }

    @Test func startToastText() {
        #expect(KeepAwakeSession(duration: .hour1, startedAt: start).startToast(clock: clock) == "Keep Awake on · until 09:00")
        #expect(KeepAwakeSession(duration: .indefinitely, startedAt: start).startToast(clock: clock) == "Keep Awake on")
    }
}

