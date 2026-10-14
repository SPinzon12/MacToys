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
        )
    ]
)
