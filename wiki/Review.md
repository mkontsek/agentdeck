# Code review, 2026-10-22

A green Debug build proved little: complete concurrency checking exposed unsafe captures, and review found missing error handling and lifecycle checks. Every finding below reproduced and was fixed.

## 1. Findings

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

## 2. Evidence

- Twenty-five XCTest tests passed at the time, with real local HTTP, PTY and WebKit activity, default-session persistence and shared skill loading.
- Strict `swift-format` lint passes; Debug and Release builds are part of verification; complete concurrency checking is on.
- The skill's frontmatter/scaffold validator passes.

## 3. Limits

- Not exercised: provider login, paid CLI/model turns, interactive canvas/keyboard behavior, Intel hardware, the macOS 14 runtime. See [[Operations]] for manual checks.
- Local processes are trusted, not authenticated. Status detection is heuristic. Git hooks can run indefinitely because subprocess timeout/cancellation is not implemented.
- None of this claims full security isolation or exhaustive end-to-end coverage. The 2026-10-25 pre-publication review is recorded in [[Decisions]].
