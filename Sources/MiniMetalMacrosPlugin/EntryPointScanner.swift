import Foundation

/// Names of the shader entry points discovered in an MSL source string,
/// bucketed by category.
struct EntryPoints {
    var vertex: [String] = []
    var fragment: [String] = []
    var compute: [String] = []

    var isEmpty: Bool {
        vertex.isEmpty && fragment.isEmpty && compute.isEmpty
    }
}

/// Scans MSL source for `vertex`, `fragment`, and `kernel` function
/// declarations and returns the function names per category.
///
/// The scanner is intentionally lightweight — it strips line and block
/// comments, then matches a simple `<keyword> <return-type> <name>(`
/// pattern. It will miss declarations that span weird whitespace or use
/// pre-name attribute syntax (`vertex [[attr]] foo bar(...)`); those are
/// rare in practice and can be tightened in a later phase if needed.
func scanEntryPoints(in source: String) -> EntryPoints {
    let cleaned = stripComments(source)
    var result = EntryPoints()
    for category in [
        ("vertex", \EntryPoints.vertex),
        ("fragment", \EntryPoints.fragment),
        ("kernel", \EntryPoints.compute),
    ] as [(String, WritableKeyPath<EntryPoints, [String]>)] {
        result[keyPath: category.1] = matchDeclarations(keyword: category.0, in: cleaned)
    }
    return result
}

// MARK: - Internals

private func matchDeclarations(keyword: String, in source: String) -> [String] {
    // Match: word-boundary keyword, whitespace, return-type token (no parens),
    // whitespace, identifier, optional whitespace, opening paren.
    //
    //   \b(keyword)[\s]+ [^\s\(\)]+ [\s]+ ([A-Za-z_][A-Za-z0-9_]*) [\s]* \(
    let pattern = #"\b\#(keyword)[\s]+[^\s\(\)]+[\s]+([A-Za-z_][A-Za-z0-9_]*)[\s]*\("#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }
    let ns = source as NSString
    let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
    var names: [String] = []
    var seen: Set<String> = []
    for m in matches where m.numberOfRanges >= 2 {
        let nameRange = m.range(at: 1)
        guard nameRange.location != NSNotFound else { continue }
        let name = ns.substring(with: nameRange)
        if seen.insert(name).inserted {
            names.append(name)
        }
    }
    return names
}

/// Removes `//` line comments and `/* */` block comments, replacing them
/// with single spaces so positions / lines outside comments are preserved
/// modulo whitespace coalescing.
private func stripComments(_ source: String) -> String {
    var out = ""
    out.reserveCapacity(source.count)
    var i = source.startIndex
    let end = source.endIndex
    while i < end {
        let c = source[i]
        let nextIdx = source.index(after: i)
        if c == "/", nextIdx < end {
            let next = source[nextIdx]
            if next == "/" {
                // Line comment — skip to newline (keep the newline).
                var j = source.index(after: nextIdx)
                while j < end, source[j] != "\n" { j = source.index(after: j) }
                out.append(" ")
                i = j
                continue
            } else if next == "*" {
                // Block comment — skip to closing "*/".
                var j = source.index(after: nextIdx)
                while j < end {
                    if source[j] == "*" {
                        let k = source.index(after: j)
                        if k < end, source[k] == "/" {
                            j = source.index(after: k)
                            break
                        }
                    }
                    j = source.index(after: j)
                }
                out.append(" ")
                i = j
                continue
            }
        }
        out.append(c)
        i = nextIdx
    }
    return out
}
