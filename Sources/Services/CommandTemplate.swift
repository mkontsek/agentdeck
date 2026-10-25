import Foundation

/// Expands the documented placeholders as literal data within zsh's common quoting contexts.
enum CommandTemplate {
    private enum Quoting { case unquoted, single, double }

    static func expand(_ template: String, values: [String: String]) -> String {
        var result = ""
        var quoting = Quoting.unquoted
        var cursor = template.startIndex
        while cursor < template.endIndex {
            let character = template[cursor]
            if character == "\\", quoting != .single {
                result.append(character)
                cursor = template.index(after: cursor)
                if cursor < template.endIndex {
                    result.append(template[cursor])
                    cursor = template.index(after: cursor)
                }
                continue
            }
            if character == "{", let end = template[cursor...].firstIndex(of: "}") {
                let key = String(template[template.index(after: cursor)..<end])
                if let value = values[key] {
                    switch quoting {
                    case .unquoted: result += "'" + singleQuoted(value) + "'"
                    case .single: result += singleQuoted(value)
                    case .double: result += doubleQuoted(value)
                    }
                    cursor = template.index(after: end)
                    continue
                }
            }
            if character == "'", quoting != .double { quoting = quoting == .single ? .unquoted : .single }
            if character == "\"", quoting != .single { quoting = quoting == .double ? .unquoted : .double }
            result.append(character)
            cursor = template.index(after: cursor)
        }
        return result
    }

    // Escaping works on Unicode scalars: a quote followed by a combining mark is one `Character`, which a
    // grapheme-based comparison would miss while the shell still sees the quote byte.
    private static func singleQuoted(_ value: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if scalar == "'" { result.append(contentsOf: "'\\''".unicodeScalars) } else { result.append(scalar) }
        }
        return String(result)
    }

    private static func doubleQuoted(_ value: String) -> String {
        let special: Set<Unicode.Scalar> = ["\\", "\"", "$", "`"]
        var result = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if special.contains(scalar) { result.append("\\") }
            result.append(scalar)
        }
        return String(result)
    }
}
