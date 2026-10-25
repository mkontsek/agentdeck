import Foundation

enum ShellError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let s) = self { return s }
        return nil
    }
}

enum Shell {
    /// Blocking runner. UI callers must use `offMain`.
    @discardableResult
    static func run(_ args: [String], cwd: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        // File-backed capture cannot deadlock when either stream fills a pipe buffer.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdout = directory.appendingPathComponent("stdout")
        let stderr = directory.appendingPathComponent("stderr")
        try Data().write(to: stdout)
        try Data().write(to: stderr)
        let out = try FileHandle(forWritingTo: stdout)
        let err = try FileHandle(forWritingTo: stderr)
        defer {
            try? out.close()
            try? err.close()
        }
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        let o = try Data(contentsOf: stdout)
        let e = try Data(contentsOf: stderr)
        let so = String(decoding: o, as: UTF8.self)
        let se = String(decoding: e, as: UTF8.self)
        if p.terminationStatus != 0 {
            throw ShellError.failed(se.isEmpty ? so : se)
        }
        return so
    }

    static func offMain<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }
}

enum Worktree {
    static func repoRoot(of dir: String) -> String? {
        guard let out = try? Shell.run(["git", "rev-parse", "--show-toplevel"], cwd: dir.expandingTilde) else {
            return nil
        }
        let s = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Creates `<root>/<repoName>/<slug>` as a new worktree on branch `agentdeck/<slug>` (or reuses the branch if it exists).
    static func create(repoDir: String, slug: String, root: String) async throws -> (
        path: String, branch: String, repo: String
    ) {
        try await Shell.offMain { try createSynchronously(repoDir: repoDir, slug: slug, root: root) }
    }

    private static func createSynchronously(repoDir: String, slug: String, root: String) throws -> (
        path: String, branch: String, repo: String
    ) {
        guard !slug.isEmpty, slug == slug.slug else {
            throw ShellError.failed("Session name needs at least one letter or digit for a worktree")
        }
        guard let repo = repoRoot(of: repoDir) else {
            throw ShellError.failed("\(repoDir) is not inside a git repository")
        }
        let repoName = URL(fileURLWithPath: repo).lastPathComponent
        let base = root.expandingTilde + "/" + repoName
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        var path = base + "/" + slug
        var n = 2
        while FileManager.default.fileExists(atPath: path) {
            path = base + "/" + slug + "-\(n)"
            n += 1
        }
        let branch = "agentdeck/" + URL(fileURLWithPath: path).lastPathComponent
        let branchExists =
            (try? Shell.run(["git", "rev-parse", "--verify", "--quiet", "refs/heads/" + branch], cwd: repo)) != nil
        if branchExists {
            try Shell.run(["git", "worktree", "add", path, branch], cwd: repo)
        } else {
            try Shell.run(["git", "worktree", "add", "-b", branch, path], cwd: repo)
        }
        return (path, branch, repo)
    }

    static func remove(repo: String, path: String) async throws {
        // Preserve uncommitted work. A dirty worktree must be handled explicitly by the user.
        _ = try await Shell.offMain { try Shell.run(["git", "worktree", "remove", "--", path], cwd: repo) }
    }
}
