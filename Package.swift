// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClickMore",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClickMore", targets: ["ClickMore"])],
    targets: [
        .target(name: "ClickMoreCore"),
        .executableTarget(name: "ClickMore", dependencies: ["ClickMoreCore"]),
        .testTarget(name: "ClickMoreCoreTests", dependencies: ["ClickMoreCore"])
    ]
)
