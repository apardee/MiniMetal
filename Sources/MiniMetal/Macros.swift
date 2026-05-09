// Public surface for MiniMetal's compile-time shader sugar.
//
// Phase 1 ships scaffolding only:
//
// - `#shader("...")` round-trips its source string into a `MetalShader` value.
// - `@MetalLayout` synthesizes an empty `mslDeclaration` and a `MetalUniform`
//   conformance. The real field-by-field translation lands in phase 2.
//
// Both macros are re-exported here so callers only need `import MiniMetal`.

/// A bundle of Metal Shading Language source plus structured entry-point
/// metadata. Currently only carries the source string; phase 3 will add
/// typed `vertex`/`fragment`/`compute` entry-point handles synthesized by
/// the `#shader` macro.
public struct MetalShader: Sendable {
    /// The MSL source that will be passed to `MTLDevice.makeLibrary(source:)`.
    public let source: String

    public init(source: String) {
        self.source = source
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
/// build time and surfaced as a `MetalShader` value.
@freestanding(expression)
public macro shader(_ source: String) -> MetalShader = #externalMacro(
    module: "MiniMetalMacrosPlugin",
    type: "ShaderMacro"
)

/// Marks a Swift struct as a Metal uniform, synthesizing an `mslDeclaration`
/// matching the struct's layout and a conformance to `MetalUniform`.
@attached(member, names: named(mslDeclaration))
@attached(extension, conformances: MetalUniform)
public macro MetalLayout() = #externalMacro(
    module: "MiniMetalMacrosPlugin",
    type: "MetalLayoutMacro"
)
