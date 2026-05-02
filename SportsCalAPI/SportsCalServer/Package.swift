// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SportsCalServer",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.0.0"),
        .package(path: "../../SportsCalModel"),
        .package(url: "https://github.com/vapor/apns.git", branch: "main"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
                .product(name: "Redis", package: "redis"),
                .product(name: "SQLiteNIO", package: "sqlite-nio"),
                .product(name: "SportsCalModel", package: "SportsCalModel"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "JWT", package: "jwt")
            ],
            swiftSettings: [
                // Enable better optimizations when building in Release configuration. Despite the use of
                // the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
                // builds. See <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production> for details.
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")]),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"),
            .product(name: "XCTVapor", package: "vapor"),
        ])
    ]
)
