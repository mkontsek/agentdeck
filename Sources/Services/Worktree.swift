import Foundation

enum ShellError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let s) = self { return s }; return nil }
}

enum Shell {
    /// Run a command synchronously (off the main thread when called from async contexts).
    @discardableResult
    static func run(_ args: [String], cwd: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let so = String(decoding: o, as: UTF8.self)
        let se = String(decoding: e, as: UTF8.self)
        if p.terminationStatus != 0 {
            throw ShellError.failed(se.isEmpty ? so : se)
        }
        return so
    }
}

enum Worktree {
    static func repoRoot(of dir: String) -> String? {
        guard let out = try? Shell.run(["git", "rev-parse", "--show-toplevel"], cwd: dir.expandingTilde) else { return nil }
        let s = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Creates `<root>/<repoName>/<slug>` as a new worktree on branch `agentdeck/<slug>` (or reuses the branch if it exists).
    static func create(repoDir: String, slug: String, root: String) throws -> (path: String, branch: String, repo: String) {
        guard let repo = repoRoot(of: repoDir) else { throw ShellError.failed("\(repoDir) is not inside a git repository") }
        let repoName = URL(fileURLWithPath: repo).lastPathComponent
        let base = root.expandingTilde + "/" + repoName
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        var path = base + "/" + slug
        var n = 2
        while FileManager.default.fileExists(atPath: path) { path = base + "/" + slug + "-\(n)"; n += 1 }
        let branch = "agentdeck/" + URL(fileURLWithPath: path).lastPathComponent
        let branchExists = (try? Shell.run(["git", "rev-parse", "--verify", "--quiet", "refs/heads/" + branch], cwd: repo)) != nil
        if branchExists {
            try Shell.run(["git", "worktree", "add", path, branch], cwd: repo)
        } else {
            try Shell.run(["git", "worktree", "add", "-b", branch, path], cwd: repo)
        }
        return (path, branch, repo)
    }

    static func remove(repo: String, path: String) throws {
        try Shell.run(["git", "worktree", "remove", "--force", path], cwd: repo)
    }
}
