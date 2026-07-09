// Core value types that the compile-time shader sugar produces and consumes.
// These are plain Swift with no swift-syntax dependency, so they live in the
// core `MiniMetal` target and are usable without opting into the macros:
//
// - `MetalShader` is what `#shader` expands to, but its `init` is public, so a
//   macro-free demo can hand-build one and still use the pipeline conveniences
//   in `Pipelines.swift`.
// - `MetalUniform` is what `@MetalLayout` conforms a struct to; the uniform
//   encoders in `Encoders.swift` constrain on it.
//
// The `#shader` / `@MetalLayout` macro declarations themselves live in the
// opt-in `MiniMetalMacros` target (`import MiniMetalMacros`), which depends on
// the swift-syntax-backed macro plugin.

/// A bundle of Metal Shading Language source plus the entry-point names
/// the `#shader` macro discovered in it. Function names are exposed as
/// `[String]` arrays — typos at call sites surface when Metal can't find
/// the function at pipeline-creation time, not at Swift compile time.
///
/// Production extraction: pass `shader.source` to a `.metal` file and
/// replace `shader.vertex` references with the bare `"vertex_main"`
/// literals you'd write in plain Metal. No further refactoring needed.
public struct MetalShader: Sendable {
    /// The MSL source that will be passed to `MTLDevice.makeLibrary(source:)`.
    public let source: String

    /// Names of declared `vertex` functions, in source order.
    public let vertex: [String]

    /// Names of declared `fragment` functions, in source order.
    public let fragment: [String]

    /// Names of declared `kernel` (compute) functions, in source order.
    public let compute: [String]

    public init(
        source: String,
        vertex: [String] = [],
        fragment: [String] = [],
        compute: [String] = []
    ) {
        self.source = source
        self.vertex = vertex
        self.fragment = fragment
        self.compute = compute
    }
}

/// A Swift type whose memory layout mirrors a Metal Shading Language struct.
/// Conformance is synthesized by `@MetalLayout`; the macro guarantees Swift
/// and MSL stride parity so the type can be passed directly to
/// `setVertexBytes`, `setFragmentBytes`, etc.
public protocol MetalUniform {
    /// The MSL `struct` declaration corresponding to this Swift type.
    static var mslDeclaration: String { get }
}
