import SwiftSyntax

/// A Metal Shading Language type with the layout it occupies as a struct
/// field. Sizes and alignments follow Apple's MSL spec, where `float3` /
/// `int3` / `uint3` are padded to 16 bytes inside a struct (matching Swift's
/// `simd_float3` etc.) so Swift and MSL field offsets agree.
struct MSLType {
    let name: String
    let size: Int
    let alignment: Int
}

/// Maps a Swift type written as a `TypeSyntax` to its MSL counterpart, or
/// `nil` if no mapping exists. The mapping is intentionally narrow — types
/// outside this table are likely to corrupt GPU reads, so the macro errors
/// rather than guesses.
func mslType(for typeSyntax: TypeSyntax) -> MSLType? {
    let name = typeSyntax.trimmedDescription
    if let direct = directScalarOrSIMDMap[name] { return direct }

    // Generic SIMD<N>: SIMD2<Float>, SIMD3<UInt32>, SIMD4<Int32>, ...
    if let identType = typeSyntax.as(IdentifierTypeSyntax.self),
       identType.name.text.hasPrefix("SIMD"),
       let count = Int(identType.name.text.dropFirst(4)),
       (2...4).contains(count),
       let generics = identType.genericArgumentClause,
       generics.arguments.count == 1
    {
        let argDesc = generics.arguments.first!.argument.trimmedDescription
        if let elem = simdElement(forSwift: argDesc) {
            return packedSIMD(element: elem, count: count)
        }
    }

    return nil
}

/// Computes the stride of an MSL struct whose fields have the given types,
/// in declaration order. Mirrors C struct layout: each field aligned to its
/// own alignment, struct stride rounded up to the max field alignment.
func computeStride(fields: [MSLType]) -> Int {
    var offset = 0
    var maxAlignment = 1
    for field in fields {
        offset = roundUp(offset, to: field.alignment)
        offset += field.size
        if field.alignment > maxAlignment { maxAlignment = field.alignment }
    }
    return roundUp(offset, to: maxAlignment)
}

private func roundUp(_ value: Int, to alignment: Int) -> Int {
    (value + alignment - 1) & ~(alignment - 1)
}

// MARK: - Mapping tables

private struct SIMDElement {
    let mslName: String
    let size: Int
}

private func simdElement(forSwift swiftName: String) -> SIMDElement? {
    switch swiftName {
    case "Float", "Float32": return SIMDElement(mslName: "float", size: 4)
    case "Int32": return SIMDElement(mslName: "int", size: 4)
    case "UInt32": return SIMDElement(mslName: "uint", size: 4)
    case "Int16": return SIMDElement(mslName: "short", size: 2)
    case "UInt16": return SIMDElement(mslName: "ushort", size: 2)
    case "Int8": return SIMDElement(mslName: "char", size: 1)
    case "UInt8": return SIMDElement(mslName: "uchar", size: 1)
    default: return nil
    }
}

/// Builds the MSL layout for `SIMDN<element>`. Per MSL spec, vec3 inside a
/// struct is padded to vec4 (size and alignment), matching Swift's `simd_X3`
/// stride.
private func packedSIMD(element: SIMDElement, count: Int) -> MSLType? {
    let mslName = "\(element.mslName)\(count)"
    switch count {
    case 2:
        return MSLType(name: mslName, size: element.size * 2, alignment: element.size * 2)
    case 3, 4:
        return MSLType(name: mslName, size: element.size * 4, alignment: element.size * 4)
    default:
        return nil
    }
}

/// Direct mapping for non-generic Swift type names. Includes the simd_*
/// typealiases that callers most commonly write.
private let directScalarOrSIMDMap: [String: MSLType] = {
    var m: [String: MSLType] = [:]

    // Scalars
    m["Float"]   = MSLType(name: "float",  size: 4, alignment: 4)
    m["Float32"] = MSLType(name: "float",  size: 4, alignment: 4)
    m["Int32"]   = MSLType(name: "int",    size: 4, alignment: 4)
    m["UInt32"]  = MSLType(name: "uint",   size: 4, alignment: 4)
    m["Int16"]   = MSLType(name: "short",  size: 2, alignment: 2)
    m["UInt16"] = MSLType(name: "ushort",  size: 2, alignment: 2)
    m["Int8"]    = MSLType(name: "char",   size: 1, alignment: 1)
    m["UInt8"]   = MSLType(name: "uchar",  size: 1, alignment: 1)
    m["Bool"]    = MSLType(name: "bool",   size: 1, alignment: 1)

    // simd vectors (typealiases for SIMD<N><Element>)
    let simdVecs: [(String, String, Int)] = [
        ("simd_float2", "float", 4), ("simd_float3", "float", 4), ("simd_float4", "float", 4),
        ("simd_int2",   "int",   4), ("simd_int3",   "int",   4), ("simd_int4",   "int",   4),
        ("simd_uint2",  "uint",  4), ("simd_uint3",  "uint",  4), ("simd_uint4",  "uint",  4),
    ]
    for (swiftName, mslElem, elemSize) in simdVecs {
        let count = Int(swiftName.suffix(1))!
        let bytes = count == 2 ? elemSize * 2 : elemSize * 4
        m[swiftName] = MSLType(name: "\(mslElem)\(count)", size: bytes, alignment: bytes)
    }

    // simd matrices: floatNxM = N columns of float-M (column-major)
    // Column size: M=2 → 8B/8A, M=3 → 16B/16A (padded), M=4 → 16B/16A
    func columnLayout(rows: Int) -> (size: Int, alignment: Int) {
        switch rows {
        case 2: return (8, 8)
        case 3, 4: return (16, 16)
        default: fatalError("unreachable")
        }
    }
    for cols in 2...4 {
        for rows in 2...4 {
            let col = columnLayout(rows: rows)
            let total = col.size * cols
            m["simd_float\(cols)x\(rows)"] = MSLType(
                name: "float\(cols)x\(rows)",
                size: total,
                alignment: col.alignment
            )
        }
    }
    return m
}()
