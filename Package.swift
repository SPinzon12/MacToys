// swift-tools-version: 6.4
import PackageDescription

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
            swiftSettings: [
                // CommandLineTools ships TestingMacros in plugins/testing/ but the
                // driver only auto-loads plugins from the flat plugins/ dir —
                // point the compiler at the swift-testing macro plugin explicitly.
                .unsafeFlags([
                    "-Xfrontend", "-load-resolved-plugin", "-Xfrontend",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib##TestingMacros"
                ])
            ]
        )
    ]
)
