// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiniMetal",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MiniMetal",
            targets: ["MiniMetal"]
        ),
        .executable(
            name: "SpinningCube",
            targets: ["SpinningCube"]
        ),
    ],
    targets: [
        .target(
            name: "MiniMetal"
        ),
        .executableTarget(
            name: "SpinningCube",
            dependencies: ["MiniMetal"],
            path: "Examples/SpinningCube"
        ),
        .testTarget(
            name: "MiniMetalTests",
            dependencies: ["MiniMetal"]
        ),
    ]
)
