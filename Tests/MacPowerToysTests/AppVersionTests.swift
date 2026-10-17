import Testing
@testable import MacPowerToys

/// The version line shown in the status menu.
struct AppVersionTests {
    @Test func bundledAppShowsVersionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "25"]
        #expect(AppVersion.label(info: info) == "Version 0.1.0 (25)")
    }

    @Test func versionWithoutBuildNumber() {
        #expect(AppVersion.label(info: ["CFBundleShortVersionString": "0.1.0"]) == "Version 0.1.0")
    }

    @Test func bareExecutableIsADevelopmentBuild() {
        // `swift run` has no Info.plist, so no version keys.
        #expect(AppVersion.label(info: nil) == "Development build")
        #expect(AppVersion.label(info: [:]) == "Development build")
    }
}
