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
    /// Added with "Add 15 Minutes".
    private(set) var extraTime: TimeInterval = 0

    init(duration: KeepAwakeDuration, startedAt: Date) {
        self.duration = duration
        self.startedAt = startedAt
    }

    var endsAt: Date? { duration.interval.map { startedAt.addingTimeInterval($0 + extraTime) } }

    /// Only a timed run has an end to push back.
    var canExtend: Bool { duration.interval != nil }

    mutating func extend(by seconds: TimeInterval) {
        guard canExtend else { return }
        extraTime += seconds
    }

    /// Seconds left, never negative; nil while running indefinitely.
    func remaining(at now: Date) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Judged by the wall clock, so a Mac woken long after the end reads as expired.
    func isExpired(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }

    /// Status line with the wall-clock end: "On — 42 min left · until 15:30".
    func statusLabel(at now: Date, clock: DateFormatter = Self.clock) -> String {
        let label = Self.statusLabel(remaining: remaining(at: now))
        guard let endsAt else { return label }
        return "\(label) · until \(clock.string(from: endsAt))"
    }

    /// Confirmation toast when a run starts ("on") or is extended ("extended").
    func startToast(_ headline: String = "Keep Awake on", clock: DateFormatter = Self.clock) -> String {
        guard let endsAt else { return headline }
        return "\(headline) · until \(clock.string(from: endsAt))"
    }

    /// The user's own short time format (12 h or 24 h, as set in System Settings).
    static var clock: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    /// The remaining-time part of the status line.
    static func statusLabel(remaining: TimeInterval?) -> String {
        guard let remaining else { return "On until you turn it off" }
        guard remaining >= 60 else { return "On — less than 1 min left" }
        // Round up: the label never promises less time than is left.
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 { return "On — \(minutes) min left" }
        return "On — \(minutes / 60) h \(String(format: "%02d", minutes % 60)) min left"
    }
}
