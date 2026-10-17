import Foundation

/// How long Keep Awake stays on.
enum KeepAwakeDuration: CaseIterable {
    case minutes15
    case hour1
    case hours2
    case hours4
    case indefinitely

    var title: String {
        switch self {
        case .minutes15: "15 Minutes"
        case .hour1: "1 Hour"
        case .hours2: "2 Hours"
        case .hours4: "4 Hours"
        case .indefinitely: "Indefinitely"
        }
    }

    /// nil = until turned off.
    var interval: TimeInterval? {
        switch self {
        case .minutes15: 15 * 60
        case .hour1: 3600
        case .hours2: 2 * 3600
        case .hours4: 4 * 3600
        case .indefinitely: nil
        }
    }
}

/// One Keep Awake run. Pure timing: the controller owns the power assertions.
struct KeepAwakeSession {
    let duration: KeepAwakeDuration
    let startedAt: Date

    var endsAt: Date? { duration.interval.map(startedAt.addingTimeInterval) }

    /// Seconds left, never negative; nil while running indefinitely.
    func remaining(at now: Date) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Judged by the wall clock, so a Mac woken long after the end reads as expired.
    func isExpired(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }

    /// The disabled status line at the top of the Keep Awake submenu.
    static func statusLabel(remaining: TimeInterval?) -> String {
        guard let remaining else { return "On until you turn it off" }
        guard remaining >= 60 else { return "On — less than 1 min left" }
        // Round up: the label never promises less time than is left.
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 { return "On — \(minutes) min left" }
        return "On — \(minutes / 60) h \(String(format: "%02d", minutes % 60)) min left"
    }
}
