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
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "MeterletCore", resources: [.process("Resources")]),
        .executableTarget(name: "Meterlet", dependencies: ["MeterletCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MeterletCoreTests", dependencies: ["MeterletCore"], resources: [.copy("Fixtures")]),
    ]
)
