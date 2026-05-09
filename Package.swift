// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "testcontainers-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TestcontainersCore", targets: ["TestcontainersCore"]),
        .library(name: "TestcontainersCompose", targets: ["TestcontainersCompose"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-server/async-http-client.git",
            "1.21.0"..<"1.31.0"
        ),
    ],
    targets: [
        .target(
            name: "TestcontainersCore",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            path: "Sources/TestcontainersCore"
        ),
        .target(
            name: "TestcontainersCompose",
            dependencies: ["TestcontainersCore"],
            path: "Sources/TestcontainersCompose"
        ),
        .testTarget(
            name: "TestcontainersCoreTests",
            dependencies: ["TestcontainersCore"],
            path: "Tests/TestcontainersCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "TestcontainersComposeTests",
            dependencies: ["TestcontainersCompose", "TestcontainersCore"],
            path: "Tests/TestcontainersComposeTests",
            resources: [.copy("compose_fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
