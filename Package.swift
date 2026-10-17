// swift-tools-version: 6.0
import Foundation
import PackageDescription

// CommandLineTools ships the swift-testing macro plugin in plugins/testing/, but the
// driver only auto-loads plugins from the flat plugins/ dir, so it is pointed at
// explicitly. A full Xcode toolchain (CI) finds it on its own; there the flag would
// load a second copy, so it is skipped when MPT_SKIP_CLT_TESTING_PLUGIN is set or
// the CommandLineTools plugin is missing.
let cltTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let useCLTTestingPlugin = ProcessInfo.processInfo.environment["MPT_SKIP_CLT_TESTING_PLUGIN"] == nil
    && FileManager.default.fileExists(atPath: cltTestingPlugin)

let package = Package(
    name: "mac-powertoys",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Product name differs from target name so `swift run mac-powertoys` works.
        .executable(name: "mac-powertoys", targets: ["MacPowerToys"])
    ],
    targets: [
        .executableTarget(
            name: "MacPowerToys",
            path: "Sources/MacPowerToys"
        ),
        .testTarget(
            name: "MacPowerToysTests",
            dependencies: ["MacPowerToys"],
            path: "Tests/MacPowerToysTests",
            swiftSettings: useCLTTestingPlugin
                ? [.unsafeFlags(["-Xfrontend", "-load-resolved-plugin", "-Xfrontend", "\(cltTestingPlugin)##TestingMacros"])]
                : []
        )
    ]
)
