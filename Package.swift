// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Meterlet",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Meterlet", targets: ["Meterlet"]),
        .library(name: "MeterletCore", targets: ["MeterletCore"]),
    ],
    targets: [
        .target(name: "MeterletCore", resources: [.process("Resources")]),
        .executableTarget(name: "Meterlet", dependencies: ["MeterletCore"]),
        .testTarget(name: "MeterletCoreTests", dependencies: ["MeterletCore"], resources: [.copy("Fixtures")]),
    ]
)
