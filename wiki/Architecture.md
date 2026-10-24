# Architecture

AgentDeck is a macOS 14+ SwiftUI app. `AppStore` owns persisted sessions, task board, runtime status, and orchestration on the main actor. `TerminalHost` owns SwiftTerm PTYs; `BrowserHost` owns persistent WebKit profiles. Views render these resources without starting processes or recreating stopped browsers.

## Repository structure

| Location | Responsibility |
| --- | --- |
| `Sources/App`, `Sources/Views` | Application lifecycle, menus, SwiftUI surfaces |
| `Sources/Store` | Session lifecycle, board, persistence, message injection |
| `Sources/Models` | Persisted value types and runtime models |
| `Sources/Terminal`, `Sources/Browser` | Native resource owners and view adapters |
| `Sources/Services` | Git subprocesses, literal shell placeholders, status heuristics |
| `Sources/Services/SkillScanner.swift`, `Sources/Store/SkillLibrary.swift` | Bounded skill discovery, enabled catalog and cached instructions |
| `Sources/MCP` | HTTP framing, loopback listener, JSON-RPC and tools |
| `Tests` | Isolated regression and local integration tests |
| `.githooks` | Opt-in pre-commit quality gate |

## Process and state boundaries

Git operations run on a background queue. File-backed stdout/stderr capture avoids pipe-capacity deadlocks while keeping diagnostics separate. Worktree creation failure stops session creation. Dirty worktree deletion fails and retains the session instead of discarding work.

Shell templates expand placeholders as literal values in unquoted, single-quoted and double-quoted argument contexts. Use environment variables for advanced shell constructs such as nested substitutions and here-documents. Templates themselves remain trusted executable code.

Delayed terminal submission verifies the terminal instance and session generation before sending Enter. Automated messages require an MCP-capable profile and a running session; plain shells accept only explicit user input. Pending messages and the first typed line wait for idle status. The start-up briefing is a file written before launch (`briefing/<id>.md`); a profile whose command contains `{briefingPath}` receives it through the command line (Claude Code: `--append-system-prompt-file`), other MCP-capable profiles are typed one pointer line. Sessions with `resumeLastConversation` run the profile's `resumeCommand` when `ResumeDetection` finds a prior conversation for the directory in the provider's own storage; a resumed session is neither briefed nor given its first prompt again. Status summaries are sent only on an explicit request (menu, pane menu, inspector) or inside the start-up briefing; there is no periodic broadcast between sessions.

PTY output does not publish store state. `TerminalHost` reports output to a private timestamp map and the one-second status tick folds it into `runtime`, republishing a session only when its runtime actually changed. The focused-pane stats strip is laid out on every pane so focus changes never resize a terminal (a resize makes the CLI repaint its whole screen).

State writes are atomic. `AppStore(stateURL:)` allows tests to use a temporary state file and MCP-config directory. An unreadable state file disables saving for that store instance and surfaces an error; the original is preserved for recovery.

Built-in agent commands include their provider's tool-permission bypass flag. When loading legacy state,
the store updates only exact previously shipped commands and preserves other profile fields. The persisted
`unrestrictedCLIDefaultsApplied` marker makes this a one-time migration so later user edits survive relaunch.
Custom commands and plain shells are not rewritten. Existing terminal processes keep their original arguments.

On startup, the store loads the skill catalog off the main actor, then restores sessions. If the session list is empty and the startup option is enabled, `DefaultSessions` chooses one interface per provider: Claude Code, Codex, Antigravity, Grok Build, and Perplexity. Google falls back to Gemini CLI when the Antigravity profile is absent; providers fall back to browsers when their CLI profiles are absent. The explicit empty-canvas action uses the same idempotent seeding method. Corrupt state blocks seeding. Plain shells and custom URLs are not automatic defaults.

Inactive pane content is covered by a native `FocusClickView` that consumes the initial mouse sequence and focuses the pane. Once focused, the overlay is removed so terminal selection and browser controls receive subsequent clicks normally. Headers and resize grips remain directly interactive.

Drag and resize gestures measure translation in the global coordinate space so moving the pane does not alter the gesture's reference frame. `PaneGridView` reports its measured viewport to the store. `CanvasLayout` calculates balanced rows for Fill Canvas, retaining minimum readable pane sizes when scrolling is necessary. Fill saves sizes and positions together. `SessionOrdering` places Claude CLI first and Codex second while preserving the order of the remaining sessions; loading, creation, Tidy, and Fill use this order independently of focus/z-order.

CLI sessions persist a `paneID`; legacy sessions default it to their own session UUID and retain separate panes.
`SessionPane` derives ordered groups from the flat session list, and `selectedPaneTabs` persists each pane's active
session. Sidebar focus and tab shortcuts update that selection and the maximized view. Canvas/Grid render one
pane per group; position, size and z-order changes apply to all members. Removing an active tab selects a neighbor,
retaining the pane's identity even when its original session is removed. Closing the last tab removes the pane.

`SessionTabs` creates a fresh session using the source's CLI, directory/worktree and font/launch preferences;
initial prompts and orchestrator roles are not copied. Each tab retains its own runtime, PTY, MCP URL and tasks.
`TerminalRepresentable` detaches hidden native views without stopping their processes, clears stale child views,
and restores keyboard focus when the selected terminal attaches. Worktree deletion refuses paths referenced by
another session. New Session continues to create an independent pane.

## Browser profiles

`AppSettings.sharedBrowserProfileID` identifies one persistent WebKit website data store for this saved workspace.
Each browser session persists a `BrowserProfileMode`: `shared` (default, including legacy sessions) or `isolated`.
`browserProfileID` remains the session's separate store identifier so upgrading or switching modes never deletes
previous individual login data. `BrowserHost` resolves the effective store identifier when creating each web view.
Switching mode recreates only a running browser pane; stopped panes remain stopped. Removing a shared pane never
deletes the shared data store. Explicit isolated-profile deletion is guarded against deleting a shared/referenced store.
No cookies are copied from Chrome or merged across old profiles. WebKit enforces normal cookie/origin boundaries.

## Agent browsers

CLI sessions never drive the user's browser. The first `browser_*` tool call from a CLI session creates a companion
browser session (`agentOwnerID` = the CLI session, `isolated` profile, same pane, created without stealing focus
or the selected tab). `Sources/Browser/BrowserAutomation.swift` implements the tools over that session's
`BrowserController`; `Sources/Browser/BrowserScripts.swift` holds the page scripts, each returning JSON. Tools act
only on the caller's own companion; browser sessions cannot call them. Companions are excluded from status
summaries, listed with `agent_browser_of` in `list_sessions`, and removed (profile deleted) with their owner.

`BrowserController` exposes `navigate` (waits for the matching `WKNavigation`, 20 s timeout), `evaluate`
(JavaScript result rendered as text/JSON) and `snapshot` (PNG). A hidden companion has no superview, so
`ensureInWindow` parks it off-screen inside the main window; WebKit's private occlusion detection is disabled for
companions so they keep rendering while other apps cover AgentDeck. Screenshots still require the window to exist.

## Skill directories

Settings persist configured root directories and disabled skill IDs (canonical manifest paths). Repository roots resolve conventional skill containers; a direct skills folder or individual package is also supported. Scanning follows symlinks with canonical-path deduplication, skips build/vendor folders, and limits depth, directory count, file size and aggregate content. It does not execute scripts. `SKILL.md` name/description frontmatter is read without adding a YAML dependency; quoted scalars and folded/literal descriptions are supported.

`SkillLibrary` caches instructions, publishes UI state, and writes an atomic Markdown catalog. Reload tasks are cancelled when superseded; removed/disabled skills are unavailable to MCP immediately during reload. `list_skills` exposes enabled metadata; `read_skill` accepts only an exact enabled ID, never an arbitrary filesystem path. The catalog is exported through child environment variables and the briefing file. Native provider configuration is unchanged. Browser use is explicit copying of instructions.

## Local MCP boundary

`MCPServer` owns listeners, connections and deadlines on the main actor. The parser rejects malformed/duplicate framing headers, negative or overflowing lengths, and transfer encoding. Limits: 16 KiB headers, 1 MiB body, 64 connections, 15 seconds to receive a request. The handler is async; the deadline is cancelled once a request is parsed so browser tools may wait on page loads (bounded by their own timeouts). A connection serves one request and closes after the response, including when a client half-closes its write side. Tool results are MCP content blocks; screenshots return an image block plus a caption.

Host and Origin must identify the exact loopback endpoint; native clients may omit Origin. There is no wildcard CORS. Tool calls require a known managed-session URL and recruit operations check the orchestrator role. Diagnostic GET endpoints remain local and readable.

Session UUIDs identify callers; they are **not authentication credentials**. Other local processes can inspect diagnostics and impersonate sessions. This is a trusted-local-machine boundary, not isolation against hostile local programs. No remote access is supported.

The supported transport is JSON over HTTP/1.1 with Content-Length. SSE, batching, chunked request bodies and HTTP pipelining are unsupported.
