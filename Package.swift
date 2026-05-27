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
        // Runnable checks for manager concurrency/config logic, executed with
        // `swift run ManagerChecks` (and `--sanitize=thread` for the race checks).
        // Deliberately uses no XCTest, so it runs with just the Command Line Tools —
        // this project is built without a full Xcode install and has no CI.
        //
        // The manager sources under test (AudioCaptureManager, HotkeyManager, and its
        // dependencies) are SYMLINKED into the ManagerChecks/ directory rather than
        // copied. SwiftPM requires a target's sources to live under its `path`, but we
        // want to exercise the real shipping files, not a fork that can drift. The
        // symlinks (git mode 120000) give SwiftPM files under ManagerChecks/ that
        // resolve to the originals in VoxKey/, so edits to the real code are picked up
        // automatically. main.swift is the only non-symlinked file here.
        //
        // This is a workaround for VoxKey being an executable target (can't be
        // `@testable import`ed). If a VoxKeyCore library target is ever split out,
        // these symlinks can be replaced by a normal target dependency + import.
        .executableTarget(
            name: "ManagerChecks",
            path: "ManagerChecks"
        )
    ]
)
