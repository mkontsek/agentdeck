import Foundation

struct LoadedSkill: Identifiable, Sendable {
    var id: String { path }
    let name: String
    let summary: String
    let path: String
    let markdown: String
}

struct SkillScan: Sendable {
    var skills: [LoadedSkill] = []
    var warnings: [String] = []
}

/// Reads standard SKILL.md packages without executing their scripts or altering source folders.
enum SkillScanner {
    static let maximumFileBytes = 256 * 1024
    private static let ignored = Set(["node_modules", "build", "DerivedData", "vendor", "dist", "target"])

    static func scan(directories: [String]) -> SkillScan {
        let manager = FileManager.default
        var result = SkillScan()
        var visited = Set<String>()
        var files = Set<String>()
        var scannedDirectories = 0
        var totalBytes = 0

        func visit(_ directory: URL, depth: Int) {
            let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
            guard depth <= 4, visited.insert(directory.path).inserted else { return }
            scannedDirectories += 1
            guard scannedDirectories <= 2048, result.skills.count < 512, totalBytes < 16 * 1024 * 1024 else { return }
            let manifest = directory.appendingPathComponent("SKILL.md").resolvingSymlinksInPath()
            if manager.fileExists(atPath: manifest.path) {
                guard files.insert(manifest.path).inserted else { return }
                do {
                    let handle = try FileHandle(forReadingFrom: manifest)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
                    guard data.count <= maximumFileBytes, let markdown = String(data: data, encoding: .utf8) else {
                        result.warnings.append("Skipped oversized or non-UTF-8 skill: \(manifest.path)")
                        return
                    }
                    let metadata = metadata(in: markdown)
                    let name = metadata["name"].flatMap { $0.isEmpty ? nil : $0 } ?? directory.lastPathComponent
                    result.skills.append(
                        LoadedSkill(
                            name: name, summary: metadata["description"] ?? "Local skill", path: manifest.path,
                            markdown: markdown))
                    totalBytes += data.count
                } catch {
                    result.warnings.append("Could not read \(manifest.path): \(error.localizedDescription)")
                }
                return
            }
            do {
                let children = try manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey])
                for child in children.sorted(by: { $0.path < $1.path }) {
                    guard !child.lastPathComponent.hasPrefix("."), !ignored.contains(child.lastPathComponent) else {
                        continue
                    }
                    let resolved = child.resolvingSymlinksInPath()
                    if (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        visit(resolved, depth: depth + 1)
                    }
                }
            } catch {
                result.warnings.append("Could not scan \(directory.path): \(error.localizedDescription)")
            }
        }

        for path in directories where !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let root = URL(fileURLWithPath: path.expandingTilde).standardizedFileURL
            let conventional = [".agents/skills", ".claude/skills", ".codex/skills", ".gemini/skills", "skills"]
                .map { root.appendingPathComponent($0) }
                .filter { manager.fileExists(atPath: $0.path) }
            if manager.fileExists(atPath: root.appendingPathComponent("SKILL.md").path) || conventional.isEmpty {
                visit(root, depth: 0)
            } else {
                for directory in conventional { visit(directory, depth: 0) }
            }
        }
        if scannedDirectories > 2048 || result.skills.count >= 512 || totalBytes >= 16 * 1024 * 1024 {
            result.warnings.append("Skill scan reached its size limit. Choose narrower skill folders.")
        }
        result.skills.sort { ($0.name.lowercased(), $0.path) < ($1.name.lowercased(), $1.path) }
        return result
    }

    /// Reads the top-level name/description scalars, including folded and literal descriptions.
    static func metadata(in markdown: String) -> [String: String] {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        var metadata: [String: String] = [:]
        var index = 1
        while index < end {
            let line = lines[index]
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(line[..<colon])
            guard key == "name" || key == "description" else {
                index += 1
                continue
            }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            index += 1
            if [">", "|", ">-", "|-", ">+", "|+"].contains(value) || value.isEmpty {
                var parts: [String] = []
                while index < end, lines[index].hasPrefix(" ") || lines[index].isEmpty {
                    parts.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                value = parts.joined(separator: " ")
            } else if value.hasPrefix("\""), value.hasSuffix("\"") {
                value =
                    (try? JSONDecoder().decode(String.self, from: Data(value.utf8)))
                    ?? String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            metadata[key] = value
        }
        return metadata
    }
}
