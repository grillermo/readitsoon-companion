// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReadItSoonCompanion",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ReadItSoonCore", targets: ["ReadItSoonCore"]),
        .executable(name: "ReadItSoonCompanion", targets: ["ReadItSoonCompanion"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "ReadItSoonCore",
            path: "Sources/ReadItSoonCore"
        ),
        .executableTarget(
            name: "ReadItSoonCompanion",
            dependencies: ["ReadItSoonCore"],
            path: "Sources/ReadItSoonCompanion"
        ),
        .testTarget(
            name: "ReadItSoonCoreUnitTests",
            dependencies: [
                "ReadItSoonCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/ReadItSoonCoreUnitTests"
        ),
        .testTarget(
            name: "ReadItSoonCoreIntegrationTests",
            dependencies: [
                "ReadItSoonCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/ReadItSoonCoreIntegrationTests"
        ),
        .testTarget(
            name: "ReadItSoonCoreE2ETests",
            dependencies: [
                "ReadItSoonCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/ReadItSoonCoreE2ETests"
        )
    ]
)
