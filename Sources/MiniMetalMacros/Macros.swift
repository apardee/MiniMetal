// Opt-in compile-time shader sugar for MiniMetal.
//
// This is the module you `import` to use the `#shader` / `@MetalLayout` macros.
// It re-exports the core `MiniMetal` module, so a single `import MiniMetalMacros`
// brings the full window API along with the macros — switching a demo onto the
// macros is just changing the product dependency and this one import.
//
// The macros expand into the plain `MetalShader` / `MetalUniform` types that
// live in core MiniMetal; the swift-syntax-backed expansion logic lives in the
// `MiniMetalMacrosPlugin` target that this module depends on.

@_exported import MiniMetal

/// Embeds Metal Shading Language source inline in Swift code, validated at
/// build time and surfaced as a `MetalShader` whose `.vertex`, `.fragment`,
/// and `.compute` arrays list the declared entry-point names.
///
/// Pass `@MetalLayout`-conforming Swift types via `using:` to have their
/// MSL declarations prepended to the source automatically — keeping the
/// Swift struct as the single source of truth for layout.
///
///     #shader(using: [Uniforms.self], """
///         vertex VertexOut vertex_main(constant Uniforms& u [[buffer(0)]]) { ... }
///         """)
@freestanding(expression)
public macro shader(
    using: [any MetalUniform.Type] = [],
    _ source: String
) -> MetalShader = #externalMacro(
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
