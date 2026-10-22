# Code review — 2026-10-22

The baseline Debug build succeeded, but that alone did not establish correctness. Complete concurrency checking exposed unsafe captures, and review found missing error handling and lifecycle checks. The changes below address reproducible failures.

| Finding | Resolution |
| --- | --- |
| Negative HTTP Content-Length could form an invalid Data range; requests were unbounded | Bounded parser with malformed/overflow/duplicate-header tests |
| Wildcard CORS and no Origin/Host validation exposed local orchestration to web callers | Exact loopback Origin/Host checks and a live hostile-origin rejection test |
| Listener state crossed concurrency boundaries; asynchronous startup failure was not reflected in UI | Main-actor ownership, actual readiness/failure callbacks, connection cleanup |
| Sequential stdout/stderr reads could deadlock; Git ran in SwiftUI body and UI callbacks | File-backed streams and background Git operations |
| Recruit worktree failure fell back to the original directory | Abort creation and leave request pending |
| Force-removing a worktree could discard uncommitted files | Refuse dirty deletion and retain the session |
| Browser body recreated a stopped WebKit controller | Render only existing live controllers; regression test renders the stopped pane |
| Delayed Enter could reach a replacement terminal; first briefing and queued messages could overlap | Terminal identity/generation checks and a post-injection quiet window |
| Automated messages could be executed by plain shells | Automated injection requires an MCP-capable profile |
| Raw placeholder interpolation allowed shell metacharacters in names/paths to execute | Literal substitution with tests for common quoting contexts |
| Invalid MCP ports could trap during UInt16 conversion | Checked conversion and UI validation |
| Corrupt state and write failures disappeared silently | Preserve unreadable state, stop overwriting it, report failures |
| Build output piped to tail masked compiler failure | Explicit Bash pipefail; tested with a failing compiler stub on macOS Make |

## Evidence and limits

Twenty-five XCTest tests pass, including actual local HTTP, PTY and WebKit activity, default-session persistence, and shared skill loading. Strict `swift-format` lint passes. Debug and Release builds are part of verification; complete concurrency checking is enabled. The skill's frontmatter/scaffold validator passes.

Provider login, paid CLI/model turns, interactive canvas/keyboard behavior, Intel hardware and macOS 14 runtime were not exercised. See [[Operations]] for manual acceptance checks.

Remaining design limits: local processes are trusted rather than authenticated; status detection is heuristic; Git hooks can run indefinitely because subprocess timeout/cancellation is not yet implemented. These are not claims of full security isolation or exhaustive end-to-end coverage.
