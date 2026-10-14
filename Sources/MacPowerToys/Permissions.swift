import AppKit
import ApplicationServices

/// Launch-time permission preflight: Screen Recording + Accessibility.
@MainActor
enum Permissions {
    // ponytail: one alert, one "open settings" button, no per-permission settings UI
    static func preflight() {
        var missing: [(name: String, pane: String)] = []
        if !CGPreflightScreenCaptureAccess() {
            missing.append(("Screen Recording", "Privacy_ScreenCapture"))
        }
        if !AXIsProcessTrusted() {
            missing.append(("Accessibility", "Privacy_Accessibility"))
        }
        guard !missing.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Mac PowerToys needs permissions"
        alert.informativeText = """
        Missing: \(missing.map(\.name).joined(separator: ", ")).
        Grant them under System Settings → Privacy & Security so the modules \
        can capture the screen and synthesize ⌘V, then relaunch the app.
        """
        // ponytail: opens the first missing pane only; relaunch after granting
        alert.addButton(withTitle: "Open \(missing[0].name) Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            open(pane: missing[0].pane)
        }
    }

    private static func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        _ = NSWorkspace.shared.open(url)
    }
}
