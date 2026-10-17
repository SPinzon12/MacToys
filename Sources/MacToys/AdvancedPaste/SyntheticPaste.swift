import AppKit
import ApplicationServices
import Carbon

/// Synthetic ⌘V via `CGEvent` (virtual key V, `.maskCommand`, keydown+keyup).
enum SyntheticPaste {
    /// Sends ⌘V, or explains the missing Accessibility permission and
    /// returns false — by then the payload is already on the clipboard, so
    /// the user can still paste manually.
    @MainActor
    @discardableResult
    static func send() -> Bool {
        guard AXIsProcessTrusted() else {
            presentAccessibilityAlert()
            return false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
        return true
    }

    @MainActor
    private static func presentAccessibilityAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Accessibility permission required"
        alert.informativeText = """
        Advanced Paste needs Accessibility access to send the synthetic ⌘V. \
        The transformed content is already on the clipboard — paste it manually, \
        or grant access under System Settings → Privacy & Security → \
        Accessibility and try again.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            _ = NSWorkspace.shared.open(url)
        }
    }
}
