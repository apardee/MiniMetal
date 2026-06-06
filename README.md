# MiniMetal

[![CI](https://github.com/apardee/MiniMetal/actions/workflows/ci.yml/badge.svg)](https://github.com/apardee/MiniMetal/actions/workflows/ci.yml)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)

A minimal Metal package for building Swift rendering demos on macOS. Spin up a new Swift project, add the `MiniMetal` dependency, and initialize a window that provides an `MTKView` — without interacting with any of the platform UI frameworks directly.

```swift
import MiniMetal

@main
struct HelloWindow {
    static func main() async throws {
        let window = try Window(
            title: "Hello",
            resolution: .init(width: 1024, height: 768))
        window.view.clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)
        await window.show { (_: Frame) in .continue }
    }
}
```

That's a working app. Swift 6.2, macOS 14+.

## From scratch

Create a new executable package and step into it:

```sh
mkdir HelloWindow && cd HelloWindow
swift package init --type executable
```

Edit `Package.swift` to target macOS 14, add `MiniMetal` as a dependency, and link it into the executable target:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HelloWindow",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apardee/MiniMetal.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "HelloWindow",
            dependencies: ["MiniMetal"]
        )
    ]
)
```

Write the demo in `Sources/HelloWindow/main.swift`. As `main.swift`, it runs top-level code directly — no `@main` type needed:

```swift
import Metal
import MiniMetal

let window = try Window(
    title: "Hello",
    resolution: .init(width: 1024, height: 768))
window.view.clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)
await window.show { (_: Frame) in .continue }
```

Then build and run:

```sh
swift run
```

A 1024×768 window opens, cleared to magenta every frame.

## Inline shaders

`@MetalLayout` annotates a Swift struct so its memory layout is mirrored as an MSL `struct` declaration, with a runtime stride check that fires once on first use if Swift and MSL disagree. `#shader` embeds MSL source as a string literal, scans it for `vertex` / `fragment` / `kernel` entry points, and (with `using:`) prepends the `@MetalLayout` declarations so the Swift struct is the single source of truth for layout.

```swift
@MetalLayout
private struct Uniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
}

private let shader = #shader(using: [Uniforms.self], """
    #include <metal_stdlib>
    using namespace metal;

    vertex VertexOut vertex_main(uint vid [[vertex_id]],
                                 constant Uniforms& u [[buffer(0)]]) { ... }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) { ... }
    """)
```

`shader.source` is the full MSL string (with the auto-prepended `Uniforms` declaration), and `shader.vertex` / `.fragment` / `.compute` are `[String]` arrays of the discovered entry-point names. Function names at use sites are bare string literals — same shape as plain Metal — so there's nothing macro-specific to unwind when extracting to production.

The shader body itself stays a string. Swift macros can validate, scan, and prepend, but they can't make MSL syntax parse as Swift; see `// language=msl` editor hints if you want syntax highlighting inside the literal.

## Convenience APIs

Thin extensions that compile down to the same Metal calls a hand-written demo would make:

| API | Replaces |
|---|---|
| `device.makeRenderPipeline(shader:vertex:fragment:color:depth:configure:)` | `makeLibrary(source:)` + descriptor + `makeRenderPipelineState` |
| `device.makeRenderPipeline(library:...)` | descriptor + `makeRenderPipelineState` |
| `device.makeComputePipeline(shader:function:)` | `makeLibrary(source:)` + `makeComputePipelineState` |
| `device.makeDepthStencilState(compare:write:)` | descriptor + `makeDepthStencilState(descriptor:)` |
| `encoder.setVertexUniforms(_:index:)` | `setVertexBytes(&v, length: MemoryLayout<T>.stride, index: i)` |
| `encoder.setFragmentUniforms(_:index:)` | same, fragment side |
| `encoder.setUniforms(_:index:)` *(compute)* | `setBytes(...)` |

Each `makeRenderPipeline` overload takes a trailing `configure: (MTLRenderPipelineDescriptor) -> Void = { _ in }` so callers can override or extend (blending, vertex descriptors, raster sample count) without retyping the basics.

`setVertexUniforms` / `setFragmentUniforms` / `setUniforms` are constrained to `T: MetalUniform`, so they only accept `@MetalLayout`-checked structs. For raw `simd_float*` values, fall back to Metal's `setVertexBytes(_:length:index:)`.

## Examples

- [`Examples/HelloWindow`](Examples/HelloWindow/HelloWindow.swift) — the smallest viable window-and-clear app.
- [`Examples/SpinningCube`](Examples/SpinningCube/SpinningCube.swift) — full inline-shader demo with `@MetalLayout` uniforms, MVP matrices, and a depth buffer.
