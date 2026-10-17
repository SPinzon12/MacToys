import Testing
@testable import MacToys

/// Permission status logic behind the Permissions window.
struct PermissionsTests {
    @Test func allGrantedOnlyWhenBothAre() {
        #expect(PermissionStatus(screenRecording: true, accessibility: true).allGranted)
        #expect(!PermissionStatus(screenRecording: true, accessibility: false).allGranted)
        #expect(!PermissionStatus(screenRecording: false, accessibility: true).allGranted)
    }

    @Test func missingNamesInMenuOrder() {
        #expect(PermissionStatus(screenRecording: false, accessibility: false).missing == [.screenRecording, .accessibility])
        #expect(PermissionStatus(screenRecording: true, accessibility: false).missing == [.accessibility])
        #expect(PermissionStatus(screenRecording: true, accessibility: true).missing.isEmpty)
    }

    @Test func resetTargetsOnlyThisAppsBundleID() {
        // `tccutil reset <service>` without a bundle id would wipe every app's grants.
        #expect(Permission.resetCommands(bundleID: "dev.spinzon12.MacToys") == [
            ["reset", "ScreenCapture", "dev.spinzon12.MacToys"],
            ["reset", "Accessibility", "dev.spinzon12.MacToys"]
        ])
        #expect(Permission.resetCommands(bundleID: nil).isEmpty)
        #expect(Permission.resetCommands(bundleID: "").isEmpty)
    }

    @Test func eachPermissionExplainsWhoNeedsIt() {
        #expect(Permission.screenRecording.title == "Screen Recording")
        #expect(Permission.accessibility.title == "Accessibility")
        // Both sample the screen themselves (the Color Picker's chip and magnifier).
        #expect(Permission.screenRecording.reason.contains("Color Picker"))
        #expect(Permission.screenRecording.reason.contains("Text Extractor"))
        #expect(Permission.accessibility.reason.contains("⌘V"))
    }
}
