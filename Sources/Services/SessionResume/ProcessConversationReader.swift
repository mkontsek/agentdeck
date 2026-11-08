import Darwin
import Foundation

/// Inspects only the managed process's open-file names or Claude's small PID metadata record.
/// Provider transcripts are never opened. Ambiguous process/file matches are not guessed.
enum ProcessConversationReader {
    static func read(profileID: String, directory: String, pid: Int32, home: String = NSHomeDirectory())
        -> SessionResumeCheckpoint?
    {
        guard pid > 0, ["claude", "codex", "grok"].contains(profileID) else { return nil }
        if let own = readProcess(profileID: profileID, directory: directory, pid: pid, home: home) { return own }
        // A custom shell wrapper can leave the provider one process below the PTY shell.
        let matches = children(of: pid).compactMap {
            readProcess(profileID: profileID, directory: directory, pid: $0, home: home)
        }
        return matches.count == 1 ? matches.first : nil
    }

    static func children(of pid: Int32) -> [Int32] {
        var pids = [Int32](repeating: 0, count: 64)
        let bytes = pids.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        guard bytes > 0 else { return [] }
        return Array(pids.prefix(min(pids.count, Int(bytes) / MemoryLayout<Int32>.size))).filter { $0 > 0 }
    }

    static func openFilePaths(pid: Int32) -> [String] {
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: 4096)
        let bytes = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return [] }
        var paths: [String] = []
        for descriptor in descriptors.prefix(min(descriptors.count, Int(bytes) / MemoryLayout<proc_fdinfo>.size))
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let read = withUnsafeMutablePointer(to: &info) {
                proc_pidfdinfo(
                    pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, $0, Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                )
            }
            guard read == MemoryLayout<vnode_fdinfowithpath>.size else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            if !path.isEmpty { paths.append(path) }
        }
        return paths
    }

    private static func readProcess(profileID: String, directory: String, pid: Int32, home: String)
        -> SessionResumeCheckpoint?
    {
        if profileID == "claude" {
            let metadata = URL(fileURLWithPath: home).appendingPathComponent(".claude/sessions/\(pid).json")
            guard belongsToCurrentProcess(metadata, pid: pid), let data = boundedData(at: metadata, limit: 65_536),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["pid"] as? Int32 == pid,
                let cwd = object["cwd"] as? String,
                URL(fileURLWithPath: cwd).standardizedFileURL.path
                    == URL(fileURLWithPath: directory).standardizedFileURL.path,
                let id = object["sessionId"] as? String, UUID(uuidString: id) != nil
            else { return nil }
            let encoded = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let path = home + "/.claude/projects/\(encoded)/\(id).jsonl"
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return SessionResumeCheckpoint(
                profileID: profileID, directory: directory, launchedAt: Date(), conversationID: id,
                conversationPath: path)
        }
        return checkpoint(profileID: profileID, directory: directory, paths: openFilePaths(pid: pid), home: home)
    }

    static func checkpoint(profileID: String, directory: String, paths: [String], home: String)
        -> SessionResumeCheckpoint?
    {
        let root = URL(fileURLWithPath: home).standardizedFileURL.path
        let matches: [SessionResumeCheckpoint] = paths.compactMap { path in
            let file = URL(fileURLWithPath: path).standardizedFileURL
            let id: String
            switch profileID {
            case "codex":
                guard file.path.hasPrefix(root + "/.codex/sessions/"), file.pathExtension == "jsonl",
                    file.lastPathComponent.hasPrefix("rollout-")
                else { return nil }
                id = String(file.deletingPathExtension().lastPathComponent.suffix(36))
            case "grok":
                guard file.path.hasPrefix(root + "/.grok/sessions/"), file.lastPathComponent == "events.jsonl" else {
                    return nil
                }
                id = file.deletingLastPathComponent().lastPathComponent
            default: return nil
            }
            guard UUID(uuidString: id) != nil else { return nil }
            return SessionResumeCheckpoint(
                profileID: profileID, directory: directory, launchedAt: Date(), conversationID: id,
                conversationPath: file.path)
        }
        let ids = Set(matches.compactMap(\.conversationID))
        return ids.count == 1 ? matches.first : nil
    }

    static func boundedData(at url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }

    private static func belongsToCurrentProcess(_ file: URL, pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let bytes = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        guard bytes == MemoryLayout<proc_bsdinfo>.size,
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return false }
        // A stale registry file must not associate a reused PID with an older conversation.
        return modified.timeIntervalSince1970 >= Double(info.pbi_start_tvsec)
    }
}
