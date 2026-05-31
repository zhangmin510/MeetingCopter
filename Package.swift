// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingCopter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", exact: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingCopter",
            path: "Sources/MeetingCopter"
        ),
        .testTarget(
            name: "MeetingCopterTests",
            dependencies: [
                "MeetingCopter",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/MeetingCopterTests"
        ),
    ]
)
