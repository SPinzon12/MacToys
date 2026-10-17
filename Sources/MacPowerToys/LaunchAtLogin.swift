import AppKit
import ServiceManagement

/// The status-menu version line, read from the bundle's Info.plist.
enum AppVersion {
    static func label(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return "Development build" // `swift run`: a bare executable, no Info.plist
        }
        guard let build = info?["CFBundleVersion"] as? String else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}

/// "Launch at Login" through `SMAppService.mainApp` (macOS 13+). Only a real
/// `.app` bundle can register; under `swift run` the menu item is disabled.
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Waiting for the user to allow it in System Settings → Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func toggle() {
        do {
            // A pending approval counts as on: clicking again cancels it.
            if isEnabled || needsApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentError(error)
            return
        }
        if needsApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not change Launch at Login"
        alert.informativeText = """
        \(error.localizedDescription)

        You can also add Mac PowerToys under System Settings → General → Login Items.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
