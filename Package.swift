// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoxKey",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "VoxKey",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "VoxKey",
            exclude: ["Resources/Info.plist", "Resources/VoxKey.entitlements"]
        ),
        .testTarget(
            name: "VoxKeyTests",
            dependencies: ["VoxKey"],
            path: "VoxKeyTests"
        ),
        // Dependency-free checks runnable with `swift run ManagerChecks` — no Xcode /
        // XCTest required. Compiles the real AudioCaptureManager.swift directly.
        .executableTarget(
            name: "ManagerChecks",
            path: "ManagerChecks"
        )
    ]
)
