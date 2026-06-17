// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VirtualDesk",
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
            name: "VirtualDesk",
            dependencies: ["CGVirtualDisplayBridge"]
        ),
        .testTarget(
            name: "VirtualDeskTests",
            dependencies: ["VirtualDesk"]
        ),
    ]
)
