// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CountPaperCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CountPaperCore", targets: ["CountPaperCore"])
    ],
    targets: [
        .target(
            name: "CountPaperCore",
            path: "CountPaper/Core"
        ),
        .testTarget(
            name: "CountPaperCoreTests",
            dependencies: ["CountPaperCore"],
            path: "CountPaper/Tests/Core"
        )
    ]
)
