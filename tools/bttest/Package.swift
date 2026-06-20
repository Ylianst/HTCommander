// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "bttest",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .executableTarget(
            name: "bttest",
            path: "Sources/bttest"
        )
    ]
)
