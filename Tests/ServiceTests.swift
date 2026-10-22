import XCTest

final class ServiceTests: XCTestCase {
    func testLargeStderrDoesNotDeadlockOrContaminateStdout() throws {
        let output = try Shell.run(["/bin/sh", "-c", "head -c 262144 /dev/zero >&2; printf success"])
        XCTAssertEqual(output, "success")
        XCTAssertThrowsError(try Shell.run(["/bin/sh", "-c", "printf failure >&2; exit 7"])) { error in
            XCTAssertEqual(error.localizedDescription, "failure")
        }
    }

    func testTemplateExpansionTreatsValuesAsData() throws {
        let value = "O'Brien \"quoted\" $(printf INJECTED) `printf BAD` \\ $HOME {cwd}"
        for template in ["printf '%s' {name}", "printf '%s' '{name}'", "printf '%s' \"{name}\""] {
            let command = CommandTemplate.expand(template, values: ["name": value, "cwd": "wrong"])
            XCTAssertEqual(try Shell.run(["/bin/zsh", "-c", command]), value)
        }
        let command = CommandTemplate.expand(
            "printf '%s' 'mcp_servers.agentdeck.url=\"{url}\"'", values: ["url": "http://127.0.0.1:4820/mcp/abc"])
        XCTAssertEqual(
            try Shell.run(["/bin/zsh", "-c", command]), "mcp_servers.agentdeck.url=\"http://127.0.0.1:4820/mcp/abc\"")
    }

    func testWorktreeCreationCollisionAndDirtyRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Shell.run(["git", "init", "-q"], cwd: repo.path)
        try Shell.run(
            [
                "git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                "commit", "--allow-empty", "-qm", "initial",
            ], cwd: repo.path)
        let first = try await Worktree.create(
            repoDir: repo.path, slug: "review", root: root.appendingPathComponent("trees").path)
        let second = try await Worktree.create(
            repoDir: repo.path, slug: "review", root: root.appendingPathComponent("trees").path)
        XCTAssertNotEqual(first.path, second.path)
        XCTAssertEqual(first.branch, "agentdeck/review")
        try Data("keep me".utf8).write(to: URL(fileURLWithPath: first.path).appendingPathComponent("untracked"))
        do {
            try await Worktree.remove(repo: repo.path, path: first.path)
            XCTFail("Dirty worktree must not be deleted")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: first.path)) }
        try await Worktree.remove(repo: repo.path, path: second.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        do {
            _ = try await Worktree.create(repoDir: repo.path, slug: "", root: root.path)
            XCTFail("Empty slug must fail")
        } catch {}
    }

    func testStatusPriorityAndModelStats() {
        let now = Date()
        let old = now.addingTimeInterval(-120)
        let settings = AppSettings()
        func status(_ lines: [String], program: String? = nil) -> SessionStatus {
            StatusHeuristics.evaluate(
                lines: lines, lastOutputAt: old, startedAt: old, settings: settings, programState: program, now: now
            ).status
        }
        XCTAssertEqual(status(["Do you want to proceed? (y/n)"]), .waitingForUser)
        XCTAssertEqual(status(["Thinking (esc to interrupt)"]), .stalled)
        XCTAssertEqual(status(["rate limit 429"]), .quotaWarning)
        XCTAssertEqual(status(["ready >"]), .idle)
        XCTAssertEqual(status(["Thinking"], program: "done"), .idle)
        let stats = StatusHeuristics.modelStats(lines: ["👋 Opus 4.1 • 63% context left"])
        XCTAssertEqual(stats.model?.lowercased(), "opus 4.1")
        XCTAssertEqual(stats.context, "63% context left")
    }
}
