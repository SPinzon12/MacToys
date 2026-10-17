import AppKit
import IOKit.pwr_mgt

/// Keeps the Mac awake with IOKit power assertions — the mechanism behind
/// `caffeinate`. macOS releases them when the process exits, so a crash can
/// never leave the Mac unable to sleep.
@MainActor
final class KeepAwakeController {
    static let shared = KeepAwakeController()

    private(set) var session: KeepAwakeSession?
    /// Called after every start, stop and setting change (menu + status icon).
    var onChange: (() -> Void)?

    private var assertions: [IOPMAssertionID] = []
    private var endTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private static let allowDisplaySleepKey = "keepAwake.allowDisplaySleep"

    private init() {
        // A Timer does not count time spent asleep, so on wake the end is
        // re-checked against the wall clock.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { KeepAwakeController.shared.expireIfNeeded() }
        }
    }

    var isActive: Bool { session != nil }

    /// Off by default: the display stays on too, like `caffeinate -di`.
    var allowDisplaySleep: Bool {
        get { UserDefaults.standard.bool(forKey: Self.allowDisplaySleepKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.allowDisplaySleepKey)
            if isActive {
                releaseAssertions()
                _ = createAssertions()
            }
            onChange?()
        }
    }

    func start(_ duration: KeepAwakeDuration) {
        releaseAssertions()
        endTimer?.invalidate()
        guard createAssertions() else {
            session = nil
            onChange?()
            presentFailure()
            return
        }
        session = KeepAwakeSession(duration: duration, startedAt: Date())
        scheduleEnd()
        onChange?()
    }

    func stop() {
        endTimer?.invalidate()
        endTimer = nil
        releaseAssertions()
        session = nil
        onChange?()
    }

    // MARK: - Timing

    private func scheduleEnd() {
        guard let endsAt = session?.endsAt else { return }
        let timer = Timer(fire: endsAt, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { KeepAwakeController.shared.expireIfNeeded() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    private func expireIfNeeded() {
        guard let session else { return }
        if session.isExpired(at: Date()) {
            stop()
        } else {
            endTimer?.invalidate()
            scheduleEnd() // woke early: re-arm for the remaining time
        }
    }

    // MARK: - Assertions

    private func createAssertions() -> Bool {
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep]
        if !allowDisplaySleep {
            types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep)
        }
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "MacToys Keep Awake" as CFString, // shown by `pmset -g assertions`
                &id
            )
            guard result == kIOReturnSuccess else {
                releaseAssertions()
                return false
            }
            assertions.append(id)
        }
        return true
    }

    private func releaseAssertions() {
        for id in assertions {
            IOPMAssertionRelease(id)
        }
        assertions.removeAll()
    }

    private func presentFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Keep Awake could not start"
        alert.informativeText = "macOS refused the request to prevent sleep. Your Mac will sleep as usual."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
