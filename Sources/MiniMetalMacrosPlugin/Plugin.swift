import SwiftCompilerPlugin
import SwiftDiagnostics
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

public struct MetalLayoutMacro {}

extension MetalLayoutMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(.init(
                node: Syntax(node),
                message: MetalLayoutDiagnostic.notAStruct
            ))
            return []
        }

        let typeName = structDecl.name.trimmedDescription
        let storedProps = collectStoredProperties(structDecl)

        var fields: [(name: String, msl: MSLType)] = []
        var hadErrors = false

        for prop in storedProps {
            guard let msl = mslType(for: prop.type) else {
                context.diagnose(.init(
                    node: Syntax(prop.type),
                    message: MetalLayoutDiagnostic.unsupportedFieldType(
                        prop.type.trimmedDescription
                    )
                ))
                hadErrors = true
                continue
            }
            fields.append((prop.name, msl))
        }

        if hadErrors {
            // Emit a placeholder so downstream references don't cascade.
            return [#"public static let mslDeclaration: String = """#]
        }

        let mslSource = renderMSLDeclaration(typeName: typeName, fields: fields)
        let expectedStride = computeStride(fields: fields.map { $0.msl })

        // Empty struct: skip the stride precondition (Swift uses 1, MSL uses 0).
        guard !fields.isEmpty else {
            return [
                "public static let mslDeclaration: String = \(literal: mslSource)"
            ]
        }

        return [
            """
            public static var mslDeclaration: String {
                _ = _miniMetalLayoutCheck
                return _miniMetalLayoutDeclaration
            }
            """,
            "private static let _miniMetalLayoutDeclaration: String = \(literal: mslSource)",
            """
            private static let _miniMetalLayoutCheck: Void = {
                let actual = MemoryLayout<Self>.stride
                let expected = \(raw: expectedStride)
                precondition(
                    actual == expected,
                    \(literal: "@MetalLayout: \(typeName) Swift stride \\(actual) does not match expected MSL stride \\(expected). Layout drift would corrupt GPU reads.")
                )
            }()
            """,
        ]
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

// MARK: - Helpers

/// A stored instance property eligible for layout translation.
private struct StoredProperty {
    let name: String
    let type: TypeSyntax
}

private func collectStoredProperties(_ structDecl: StructDeclSyntax) -> [StoredProperty] {
    var result: [StoredProperty] = []
    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

        // Skip type-level (static/class) properties.
        let isTypeLevel = varDecl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
        if isTypeLevel { continue }

        for binding in varDecl.bindings {
            // A binding is "stored" if it has no accessor block, or only
            // willSet/didSet observers.
            let isStored: Bool
            if let accessors = binding.accessorBlock {
                switch accessors.accessors {
                case .accessors(let list):
                    isStored = list.allSatisfy { acc in
                        let kind = acc.accessorSpecifier.tokenKind
                        return kind == .keyword(.willSet) || kind == .keyword(.didSet)
                    }
                case .getter:
                    isStored = false
                }
            } else {
                isStored = true
            }
            guard isStored else { continue }

            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation
            else { continue }

            result.append(StoredProperty(
                name: pattern.identifier.text,
                type: typeAnnotation.type
            ))
        }
    }
    return result
}

private func renderMSLDeclaration(
    typeName: String,
    fields: [(name: String, msl: MSLType)]
) -> String {
    if fields.isEmpty {
        return "struct \(typeName) {};"
    }
    let body = fields
        .map { "    \($0.msl.name) \($0.name);" }
        .joined(separator: "\n")
    return "struct \(typeName) {\n\(body)\n};"
}

// MARK: - Diagnostics

struct MetalLayoutDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    private init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "MiniMetal.MetalLayout", id: id)
        self.severity = severity
    }

    static let notAStruct = MetalLayoutDiagnostic(
        "@MetalLayout can only be applied to a struct.",
        id: "notAStruct"
    )

    static func unsupportedFieldType(_ name: String) -> MetalLayoutDiagnostic {
        MetalLayoutDiagnostic(
            "@MetalLayout: type '\(name)' has no MSL mapping. " +
            "Supported: Float, Int32, UInt32, Bool, simd_float[2-4], simd_int[2-4], " +
            "simd_uint[2-4], simd_float[N]x[M], or SIMD<N><Element>.",
            id: "unsupportedField"
        )
    }
}
