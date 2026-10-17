import Foundation
import Testing
@testable import MacToys

/// Short labels the menu-bar panel shows.
struct MenuPanelTests {
    @Test func keepAwakeChipLabels() {
        #expect(KeepAwakeDuration.allCases.map(\.shortTitle) == ["15m", "1h", "2h", "4h", "∞"])
    }

    @Test func permissionSummary() {
        #expect(PermissionStatus(screenRecording: true, accessibility: true).summary == "Ready")
        #expect(PermissionStatus(screenRecording: false, accessibility: true).summary == "1 permission missing")
        #expect(PermissionStatus(screenRecording: false, accessibility: false).summary == "2 permissions missing")
    }

    @Test func keepAwakeCardSubtitle() {
        #expect(KeepAwakeSession.cardSubtitle(nil) == "Off — your Mac sleeps as usual")

        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = TimeZone(identifier: "UTC")
        clock.dateFormat = "HH:mm"
        let start = Date(timeIntervalSince1970: 1_800_000_000) // 08:00 UTC
        let timed = KeepAwakeSession(duration: .hour1, startedAt: start)
        #expect(KeepAwakeSession.cardSubtitle(timed, now: start.addingTimeInterval(18 * 60), clock: clock)
                == "42 min left · until 09:00")
        let forever = KeepAwakeSession(duration: .indefinitely, startedAt: start)
        #expect(KeepAwakeSession.cardSubtitle(forever, now: start, clock: clock) == "Until you turn it off")
    }
}
