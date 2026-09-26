import Foundation

/// Parses the YAML frontmatter at the top of a `SKILL.md` file.
///
/// Only the subset skills use is supported: `key: value` pairs, quoted values,
/// and `|` or `>` block values made of indented lines. Nested keys are flattened
/// as `parent.child`.
public enum SkillManifest {
    public static let fileName = "SKILL.md"

    public static func parseFrontmatter(_ text: String) -> [String: String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("\u{FEFF}") {
            lines[0] = String(first.dropFirst())
        }
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return [:]
        }
        var body: [String] = []
        var closed = false
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                closed = true
                break
            }
            body.append(line)
        }
        guard closed else { return [:] }

        var result: [String: String] = [:]
        var index = 0
        var parent: (key: String, indent: Int)?

        while index < body.count {
            let line = body[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }

            let indent = line.prefix(while: { $0 == " " }).count
            if let current = parent, indent <= current.indent {
                parent = nil
            }
            let rawKey = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let key = parent.map { "\($0.key).\(rawKey)" } ?? rawKey
            let rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if rest.isEmpty {
                // Either a nested mapping or an empty value.
                parent = (key, indent)
                continue
            }

            if rest.hasPrefix("|") || rest.hasPrefix(">") {
                let folded = rest.hasPrefix(">")
                var block: [String] = []
                while index < body.count {
                    let next = body[index]
                    let nextIndent = next.prefix(while: { $0 == " " }).count
                    if !next.trimmingCharacters(in: .whitespaces).isEmpty && nextIndent <= indent {
                        break
                    }
                    block.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                while block.last?.isEmpty == true { block.removeLast() }
                result[key] = folded ? foldLines(block) : block.joined(separator: "\n")
                continue
            }

            result[key] = unquote(stripComment(rest))
        }
        return result
    }

    private static func foldLines(_ lines: [String]) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            if line.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs.joined(separator: "\n")
    }

    private static func stripComment(_ value: String) -> String {
        guard let first = value.first, first != "\"", first != "'" else { return value }
        if let range = value.range(of: " #") {
            return String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else { return value }
        if first == "\"" && last == "\"" {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
        }
        if first == "'" && last == "'" {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value
    }
}
