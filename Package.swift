// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReadItSoonCompanion",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "ReadItSoonCompanion",
            path: "Sources"
        )
    ]
)
