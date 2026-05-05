// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NvEnvyCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "NvEnvyCore", targets: ["NvEnvyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "NvEnvyCore",
            dependencies: [
                "Yams",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .testTarget(
            name: "NvEnvyCoreTests",
            dependencies: ["NvEnvyCore"]
        ),
    ]
)
