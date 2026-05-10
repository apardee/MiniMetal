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

public struct ShaderMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        var sourceArg: ExprSyntax?
        var usingArg: ExprSyntax?

        for arg in node.arguments {
            switch arg.label?.text {
            case "using":
                usingArg = arg.expression
            case nil:
                sourceArg = arg.expression
            default:
                continue
            }
        }

        guard let firstArg = sourceArg else {
            context.diagnose(.init(
                node: Syntax(node),
                message: ShaderDiagnostic.missingSource
            ))
            return emptyShaderExpr()
        }

        guard let source = extractStaticStringContent(firstArg) else {
            context.diagnose(.init(
                node: Syntax(firstArg),
                message: ShaderDiagnostic.notLiteralString
            ))
            return emptyShaderExpr()
        }

        let usingTypeNames: [String]
        if let usingArg {
            if let names = extractTypeMetatypeNames(from: usingArg) {
                usingTypeNames = names
            } else {
                context.diagnose(.init(
                    node: Syntax(usingArg),
                    message: ShaderDiagnostic.usingNotArrayLiteral
                ))
                usingTypeNames = []
            }
        } else {
            usingTypeNames = []
        }

        let entries = scanEntryPoints(in: source)
        if entries.isEmpty {
            context.diagnose(.init(
                node: Syntax(firstArg),
                message: ShaderDiagnostic.noEntryPointsFound
            ))
        }

        let referenced = scanReferencedExternalTypes(in: source)
        let declared = scanDeclaredStructs(in: source)
        let usingSet = Set(usingTypeNames)

        for ref in referenced where !declared.contains(ref) && !usingSet.contains(ref) {
            context.diagnose(.init(
                node: Syntax(firstArg),
                message: ShaderDiagnostic.typeReferencedNotInUsing(ref)
            ))
        }
        if let usingArg {
            let referencedSet = Set(referenced)
            for usingName in usingTypeNames where !referencedSet.contains(usingName) {
                context.diagnose(.init(
                    node: Syntax(usingArg),
                    message: ShaderDiagnostic.unusedUsingType(usingName)
                ))
            }
        }

        let vertexLiteral = renderStringArray(entries.vertex)
        let fragmentLiteral = renderStringArray(entries.fragment)
        let computeLiteral = renderStringArray(entries.compute)
        let sourceExpr = renderSourceExpression(userSource: firstArg, prepend: usingTypeNames)

        return """
            MetalShader(
                source: \(sourceExpr),
                vertex: \(raw: vertexLiteral),
                fragment: \(raw: fragmentLiteral),
                compute: \(raw: computeLiteral)
            )
            """
    }
}

private func renderStringArray(_ names: [String]) -> String {
    if names.isEmpty { return "[]" }
    let quoted = names.map { #""\#($0)""# }.joined(separator: ", ")
    return "[\(quoted)]"
}

/// Builds the runtime source expression. When `using:` types are listed,
/// prepends `#include <metal_stdlib>` and `using namespace metal;` so the
/// auto-generated MSL declarations (which use unqualified `float4x4` etc.)
/// can resolve those names — the user's source can repeat the include and
/// the using-directive harmlessly.
private func renderSourceExpression(userSource: ExprSyntax, prepend: [String]) -> ExprSyntax {
    if prepend.isEmpty { return userSource }
    let header = ##""#include <metal_stdlib>\nusing namespace metal;\n""##
    let prefix = prepend
        .map { #"\#($0).mslDeclaration + "\n""# }
        .joined(separator: " + ")
    return "\(raw: header) + \(raw: prefix) + \(userSource)"
}

private func extractStaticStringContent(_ expr: ExprSyntax) -> String? {
    guard let strLit = expr.as(StringLiteralExprSyntax.self) else { return nil }
    var content = ""
    for segment in strLit.segments {
        guard let textSeg = segment.as(StringSegmentSyntax.self) else {
            // Interpolation segment — phase 3 doesn't support \(...) in source.
            return nil
        }
        content += textSeg.content.text
    }
    return content
}

/// Extracts the type names from a `[T1.self, T2.self, ...]` array literal.
/// Returns nil if the expression isn't an array literal of `Type.self`
/// member-access expressions.
private func extractTypeMetatypeNames(from expr: ExprSyntax) -> [String]? {
    guard let arrayExpr = expr.as(ArrayExprSyntax.self) else { return nil }
    var names: [String] = []
    for element in arrayExpr.elements {
        guard let memberAccess = element.expression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "self",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self)
        else {
            return nil
        }
        names.append(base.baseName.text)
    }
    return names
}

private func emptyShaderExpr() -> ExprSyntax {
    "MetalShader(source: \"\")"
}

struct ShaderDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    private init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "MiniMetal.shader", id: id)
        self.severity = severity
    }

    static let missingSource = ShaderDiagnostic(
        "#shader requires a string literal source argument.",
        id: "missingSource"
    )

    static let notLiteralString = ShaderDiagnostic(
        "#shader source must be a plain string literal — interpolations and " +
        "non-literal expressions aren't supported in this version.",
        id: "notLiteralString"
    )

    static let noEntryPointsFound = ShaderDiagnostic(
        "#shader source declares no `vertex`, `fragment`, or `kernel` " +
        "functions — the resulting handle won't expose any entry points.",
        id: "noEntryPointsFound",
        severity: .warning
    )

    static let usingNotArrayLiteral = ShaderDiagnostic(
        "#shader `using:` must be an array literal of `Type.self` expressions.",
        id: "usingNotArrayLiteral"
    )

    static func typeReferencedNotInUsing(_ name: String) -> ShaderDiagnostic {
        ShaderDiagnostic(
            "#shader: source references `\(name)` from an address-space slot " +
            "but it isn't declared in the source nor passed via `using:`. " +
            "Add `\(name).self` to `using:` so its MSL declaration is prepended.",
            id: "typeReferencedNotInUsing",
            severity: .warning
        )
    }

    static func unusedUsingType(_ name: String) -> ShaderDiagnostic {
        ShaderDiagnostic(
            "#shader: type `\(name)` is in `using:` but isn't referenced in " +
            "the MSL source — its declaration will be prepended unused.",
            id: "unusedUsingType",
            severity: .warning
        )
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
