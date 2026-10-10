// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClickMore",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClickMore", targets: ["ClickMore"])],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.3")
    ],
    targets: [
        .target(name: "ClickMoreCore"),
        .executableTarget(name: "ClickMore", dependencies: [
            "ClickMoreCore",
            .product(name: "PermissionFlow", package: "PermissionFlow")
        ]),
        .testTarget(name: "ClickMoreCoreTests", dependencies: ["ClickMoreCore"])
    ]
)
