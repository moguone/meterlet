// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenViewer",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenViewer", targets: ["TokenViewer"]),
        .library(name: "TokenViewerCore", targets: ["TokenViewerCore"]),
    ],
    targets: [
        .target(name: "TokenViewerCore", resources: [.process("Resources")]),
        .executableTarget(name: "TokenViewer", dependencies: ["TokenViewerCore"]),
        .testTarget(name: "TokenViewerCoreTests", dependencies: ["TokenViewerCore"], resources: [.copy("Fixtures")]),
    ]
)
