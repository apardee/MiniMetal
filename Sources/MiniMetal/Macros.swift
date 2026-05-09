// Public surface for MiniMetal's compile-time shader sugar.
//
// Phase 3 ships:
//
// - `#shader("...")` scans the MSL source for vertex / fragment / kernel
//   entry points and returns a `MetalShader` whose `.vertex`, `.fragment`,
//   and `.compute` members expose the discovered names as compile-time
//   typed properties — typos become compile errors.
// - `@MetalLayout` synthesizes `mslDeclaration` from a Swift struct's
//   stored properties and a runtime stride check that fires on first use.
//
// Both are re-exported here so callers only need `import MiniMetal`.

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

/// Embeds Metal Shading Language source inline in Swift code, validated at
/// build time and surfaced as a `MetalShader` whose `.vertex`, `.fragment`,
/// and `.compute` arrays list the declared entry-point names.
@freestanding(expression)
public macro shader(_ source: String) -> MetalShader = #externalMacro(
    module: "MiniMetalMacrosPlugin",
    type: "ShaderMacro"
)

/// Marks a Swift struct as a Metal uniform, synthesizing an `mslDeclaration`
/// matching the struct's layout and a conformance to `MetalUniform`. A
/// runtime stride check fires once on first access to `mslDeclaration` and
/// preconditions if Swift's layout drifts from the computed MSL layout.
@attached(member, names: named(mslDeclaration), arbitrary)
@attached(extension, conformances: MetalUniform)
public macro MetalLayout() = #externalMacro(
    module: "MiniMetalMacrosPlugin",
    type: "MetalLayoutMacro"
)
