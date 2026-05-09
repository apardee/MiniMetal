// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "MiniMetal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MiniMetal",
            targets: ["MiniMetal"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
    ],
    targets: [
        .macro(
            name: "MiniMetalMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "MiniMetal",
            dependencies: ["MiniMetalMacrosPlugin"]
        ),
        .executableTarget(
            name: "HelloWindow",
            dependencies: ["MiniMetal"],
            path: "Examples/HelloWindow"
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
