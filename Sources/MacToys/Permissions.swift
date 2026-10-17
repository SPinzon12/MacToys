import AppKit
import ApplicationServices

/// The two TCC permissions the modules need.
enum Permission: CaseIterable {
    case screenRecording
    case accessibility

    var title: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    /// Who needs it, in plain words, for the Permissions window.
    var reason: String {
        switch self {
        case .screenRecording: "Color Picker and Text Extractor read the pixels on screen."
        case .accessibility: "Clipboard History pastes into the app you were using (⌘V)."
        }
    }

    var symbol: String {
        switch self {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        }
    }

    /// `tccutil` service name, used by "Reset".
    var tccService: String {
        switch self {
        case .screenRecording: "ScreenCapture"
        case .accessibility: "Accessibility"
        }
    }

    var settingsPane: String {
        switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
    }

    /// `tccutil` argument lists that forget this app's grants — and only this
    /// app's: without a bundle id `tccutil reset` would wipe every app's.
    static func resetCommands(bundleID: String?) -> [[String]] {
        guard let bundleID, !bundleID.isEmpty else { return [] }
        return allCases.map { ["reset", $0.tccService, bundleID] }
    }
}

struct PermissionStatus: Equatable {
    var screenRecording: Bool
    var accessibility: Bool

    var allGranted: Bool { screenRecording && accessibility }

    /// One line for the panel's status chip.
    var summary: String {
        switch missing.count {
        case 0: "Ready"
        case 1: "1 permission missing"
        default: "\(missing.count) permissions missing"
        }
    }

    var missing: [Permission] {
        Permission.allCases.filter { !isGranted($0) }
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .screenRecording: screenRecording
        case .accessibility: accessibility
        }
    }
}

/// Reads and requests the permissions. The request calls matter: only they add
/// MacToys to the lists in System Settings — a plain check never does, which
/// left users searching for an app that was not there.
@MainActor
enum Permissions {
    static var current: PermissionStatus {
        PermissionStatus(
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }

    /// Shows the system prompt (first time) and opens the right pane.
    static func request(_ permission: Permission) {
        switch permission {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            // "AXTrustedCheckOptionPrompt" is kAXTrustedCheckOptionPrompt's value;
            // the global itself is not concurrency-safe under Swift 6.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        openSettings(for: permission)
    }

    static func openSettings(for permission: Permission) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)")!
        _ = NSWorkspace.shared.open(url)
    }

    /// Running as a real app bundle (not `swift run`, where the terminal owns
    /// the permissions).
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Forgets this app's stale grants (after an update, an ad-hoc rebuild
    /// changes the code signature and old grants silently stop matching).
    static func resetGrants() -> Bool {
        let commands = Permission.resetCommands(bundleID: Bundle.main.bundleIdentifier)
        guard !commands.isEmpty else { return false }
        for arguments in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = arguments
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return false
            }
            guard process.terminationStatus == 0 else { return false }
        }
        return true
    }

    /// Screen Recording only takes effect in a new process.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait until this instance has really quit, then open a fresh one: a
        // fixed delay could start a second copy (two icons, clashing hotkeys).
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$0\"",
            path, pid
        ]
        try? process.run()
        NSApp.terminate(nil)
    }
}
