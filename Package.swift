// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "limitbar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "limitbar", targets: ["limitbar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "limitbar"
        ),
        .testTarget(
            name: "limitbarTests",
            dependencies: [
                "limitbar",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
