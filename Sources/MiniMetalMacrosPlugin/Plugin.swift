import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct MiniMetalMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ShaderMacro.self,
        MetalLayoutMacro.self,
    ]
}

// MARK: - #shader

/// Phase 1 stub: round-trips its string argument into a `MetalShader` value
/// with empty entry-point sets. Real entry-point extraction lands in phase 3.
public struct ShaderMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let source = node.arguments.first?.expression else {
            return #"MetalShader(source: "")"#
        }
        return "MetalShader(source: \(source))"
    }
}

// MARK: - @MetalLayout

/// Phase 1 stub: synthesizes an empty `mslDeclaration` and a conformance
/// to `MetalUniform`. Real Swift-to-MSL field translation lands in phase 2.
public struct MetalLayoutMacro {}

extension MetalLayoutMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [#"public static let mslDeclaration: String = """#]
    }
}

extension MetalLayoutMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [
            try ExtensionDeclSyntax("extension \(type.trimmed): MetalUniform {}")
        ]
    }
}
