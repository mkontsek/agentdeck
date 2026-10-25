import Foundation

enum DownloadEvent: Equatable {
    case saved(URL)
    case failed(String)
}

/// Resolves the folder browser downloads use and a safe file name inside it.
enum DownloadLocation {
    /// The Mac Downloads directory, stored with a tilde when it lives in the home folder.
    static var defaultSetting: String {
        let path =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
        return path.abbreviatingHome
    }

    static func directory(from setting: String) -> URL {
        let trimmed = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.isEmpty ? defaultSetting : trimmed
        let path: String
        if raw.hasPrefix("/") || raw.hasPrefix("~") {
            path = raw.expandingTilde
        } else {
            path = ("~/" + raw).expandingTilde
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// A single path component. Suggested names cannot leave the download folder.
    static func filename(suggested: String) -> String {
        var name = (suggested as NSString).lastPathComponent.replacingOccurrences(of: "\0", with: "")
        name = String(
            name.unicodeScalars.filter { scalar in
                scalar != "/" && scalar != ":" && !CharacterSet.controlCharacters.contains(scalar)
            })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { name = "download" }
        guard name.count > 200 else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let room = max(1, 200 - (ext.isEmpty ? 0 : ext.count + 1))
        let cut = String(stem.prefix(room))
        return ext.isEmpty ? cut : "\(cut).\(ext)"
    }

    static func destinationURL(directory: URL, suggestedFilename: String, exists: (URL) -> Bool) -> URL {
        let name = filename(suggested: suggestedFilename)
        let first = directory.appendingPathComponent(name)
        if !exists(first) { return first }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var suffix = 1
        while suffix < 1000 {
            let next = ext.isEmpty ? "\(stem) (\(suffix))" : "\(stem) (\(suffix)).\(ext)"
            let url = directory.appendingPathComponent(next)
            if !exists(url) { return url }
            suffix += 1
        }
        let fallback = ext.isEmpty ? "\(stem) \(UUID().uuidString)" : "\(stem) \(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(fallback)
    }
}
