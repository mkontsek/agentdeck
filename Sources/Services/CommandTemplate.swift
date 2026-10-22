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
                    case .unquoted: result += "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
                    case .single: result += value.replacingOccurrences(of: "'", with: "'\\''")
                    case .double:
                        for scalar in value {
                            if "\\\"$`".contains(scalar) { result.append("\\") }
                            result.append(scalar)
                        }
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
}
