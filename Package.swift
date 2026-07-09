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
        ),
        // Opt-in: adds the `#shader` / `@MetalLayout` macros (and their
        // swift-syntax build cost) on top of core MiniMetal. Depend on this
        // product instead of "MiniMetal" to use the inline-shader sugar.
        .library(
            name: "MiniMetalMacros",
            targets: ["MiniMetalMacros"]
        ),
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
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        // Core library — no macro plugin, so `import MiniMetal` carries no
        // swift-syntax build cost.
        .target(
            name: "MiniMetal"
        ),
        // Opt-in macro surface. Re-exports MiniMetal, so `import MiniMetalMacros`
        // brings the window API along with the `#shader` / `@MetalLayout` macros.
        .target(
            name: "MiniMetalMacros",
            dependencies: ["MiniMetalMacrosPlugin", "MiniMetal"]
        ),
        .executableTarget(
            name: "HelloTriangle",
            dependencies: ["MiniMetal"],
            path: "Examples/HelloTriangle"
        ),
        .executableTarget(
            name: "HelloWindow",
            dependencies: ["MiniMetal"],
            path: "Examples/HelloWindow"
        ),
        .executableTarget(
            name: "SpinningCube",
            dependencies: ["MiniMetalMacros"],
            path: "Examples/SpinningCube"
        ),
        .testTarget(
            name: "MiniMetalTests",
            dependencies: ["MiniMetalMacros"]
        ),
    ]
)
