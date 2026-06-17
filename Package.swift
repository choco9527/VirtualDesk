// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DeskBridge",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "CGVirtualDisplayBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "DeskBridge",
            dependencies: ["CGVirtualDisplayBridge"]
        ),
        .testTarget(
            name: "DeskBridgeTests",
            dependencies: ["DeskBridge"]
        ),
    ]
)
