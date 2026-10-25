# Architecture

`AppStore` owns sessions, board, runtime status and orchestration on the main actor; `TerminalHost` owns SwiftTerm PTYs; `BrowserHost` owns WebKit profiles. Views render these resources and never start processes or recreate stopped browsers. macOS 14+, SwiftUI.

## 1. Repository structure

| Location | Responsibility |
| --- | --- |
| `Sources/App`, `Sources/Views` | lifecycle, menus, SwiftUI surfaces |
| `Sources/Store` | session lifecycle, board, persistence, injection |
| `Sources/Models` | persisted value types, runtime models |
| `Sources/Terminal`, `Sources/Browser` | native resource owners and view adapters |
| `Sources/Services` | git subprocesses, literal shell placeholders, status heuristics |
| `Sources/Services/SkillScanner.swift`, `Sources/Store/SkillLibrary.swift` | bounded skill discovery, enabled catalog, cached instructions |
| `Sources/MCP` | HTTP framing, loopback listener, JSON-RPC, tools |
| `Tests` | isolated regression and local integration tests |
| `.githooks` | opt-in pre-commit gate |

## 2. Processes and shell

- Git runs on a background queue with file-backed stdout/stderr, so a full pipe cannot deadlock and diagnostics stay separate.
- Worktree creation failure stops session creation. Dirty worktree deletion fails and keeps the session. Deletion refuses paths another session references and passes `--` before the path.
- Shell templates expand placeholders as literal values in unquoted, single-quoted and double-quoted contexts, escaping by Unicode scalar. Templates themselves are trusted code. Use environment variables for nested substitutions and here-documents.
- Built-in commands carry the provider's permission-bypass flag. Legacy state is upgraded only for exact previously shipped commands; the persisted `unrestrictedCLIDefaultsApplied` marker makes it one-time. Custom commands, plain shells and running processes are untouched.

## 3. Injection and briefing

- Delayed Enter checks terminal identity and session generation before sending.
- Automated messages need an MCP-capable profile and a running session; plain shells accept only explicit user input. Queued messages and the first typed line wait for idle. Control characters are dropped.
- The briefing is a file written before launch (`briefing/<id>.md`). A command containing `{briefingPath}` receives it on the command line (Claude Code: `--append-system-prompt-file`); other MCP profiles get one typed pointer line.
- `resumeLastConversation` runs the profile's `resumeCommand` when `ResumeDetection` finds a prior conversation for the directory in the provider's storage. A resumed session is neither briefed nor given its first prompt.
- Status summaries go out only on explicit request (menu, pane menu, inspector) or inside the start-up briefing. There is no periodic broadcast.

## 4. State and rendering

- PTY output never publishes store state. `TerminalHost` records timestamps privately; the one-second tick folds them into `runtime` and republishes a session only when it changed.
- The stats strip is laid out on every pane, so focus changes never resize a terminal (a resize makes the CLI repaint).
- State writes are atomic. `AppStore(stateURL:)` lets tests use temporary state and MCP-config directories. An unreadable state file disables saving for that instance, surfaces an error and is preserved.
- Startup loads the skill catalog off the main actor, then restores sessions. With no sessions and the option on, `DefaultSessions` seeds one interface per provider: Claude Code, Codex, Antigravity, Grok Build, Perplexity; Gemini CLI replaces a missing Antigravity profile, browsers replace missing CLI profiles. The empty-canvas action uses the same idempotent seeding. Corrupt state blocks seeding. Shells and custom URLs are never defaults.
- A native `FocusClickView` covers inactive pane content, consumes the first mouse sequence and focuses the pane; it is removed once focused. Headers and resize grips stay interactive.
- Drag and resize measure translation in global coordinates. `PaneGridView` reports its viewport; `CanvasLayout` computes balanced rows for Fill Canvas with readable minimums, saving sizes and positions together. `SessionOrdering` puts Claude CLI first and Codex second for loading, creation, Tidy and Fill, independent of focus and z-order.

## 5. Panes and tabs

- CLI sessions persist a `paneID`; legacy sessions default to their own UUID and keep separate panes.
- `SessionPane` groups the flat session list; `selectedPaneTabs` persists each pane's active session. Sidebar focus and tab shortcuts update selection and the maximized view.
- Position, size and z-order apply to all members of a pane. Removing the active tab selects a neighbor and keeps the pane identity; closing the last tab removes the pane.
- `SessionTabs` clones the source's CLI, directory/worktree and font/launch preferences; not the initial prompt or orchestrator role. `resumeLastConversation` is off for tabs. Each tab has its own runtime, PTY, MCP URL and tasks.
- `TerminalRepresentable` detaches hidden native views without stopping processes, clears stale children and restores keyboard focus on attach. New Session still creates an independent pane.

## 6. Browser profiles and downloads

- `AppSettings.sharedBrowserProfileID` names one persistent WebKit data store per workspace. Each browser session persists a `BrowserProfileMode`: `shared` (default, including legacy) or `isolated`.
- `browserProfileID` stays the session's separate store, so upgrades and mode switches never delete old login data. `BrowserHost` resolves the effective store per web view.
- Switching mode recreates only a running pane. Removing a shared pane never deletes the shared store; isolated-profile deletion refuses shared or referenced stores. No cookies are copied from Chrome or merged across profiles.
- Downloads use `AppSettings.downloadDirectory`; empty resolves to the Mac Downloads folder. `BrowserController` accepts a `WKDownload` for download navigations, unshowable responses and `Content-Disposition: attachment`. The name is one path component; collisions get ` (n)`; the folder is created on demand. Success is logged; failure is logged and alerted.

## 7. Agent browsers

- The first `browser_*` call from a CLI session creates a companion session: `agentOwnerID` = the CLI, `isolated` profile locked (no switch to shared), same pane, created without stealing focus or the selected tab.
- `Sources/Browser/BrowserAutomation.swift` implements the tools over the companion's `BrowserController`; `Sources/Browser/BrowserScripts.swift` holds the page scripts, each returning JSON.
- Tools act only on the caller's companion; browser sessions cannot call them. Companions are excluded from status summaries, listed with `agent_browser_of` in `list_sessions`, and removed with their owner, profile included.
- `BrowserController` offers `navigate` (waits for the matching `WKNavigation`, 20 s timeout), `evaluate` (60 s deadline, resumed once, result as text/JSON) and `snapshot` (PNG).
- A hidden companion has no superview, so `ensureInWindow` parks it off-screen in the main window; WebKit's private occlusion detection is disabled for companions. Screenshots need the window to exist.

## 8. Skill directories

- Settings persist root directories and disabled skill IDs (canonical manifest paths). Repository roots resolve conventional containers; a direct skills folder or single package also works.
- Scanning follows symlinks with canonical deduplication, but a manifest must resolve to a regular file inside a configured directory: a link into another configured folder passes, a link to `~/.ssh` is skipped with a warning.
- Build/vendor folders are skipped; depth, directory count, file size and total content are bounded. Scripts never execute.
- `SKILL.md` name/description frontmatter is parsed without a YAML dependency, including quoted scalars and folded/literal descriptions.
- `SkillLibrary` caches instructions, publishes UI state and writes an atomic Markdown catalog. Superseded reloads are cancelled; removed or disabled skills vanish from MCP immediately.
- `list_skills` exposes enabled metadata; `read_skill` accepts only an exact enabled ID. The catalog reaches agents through environment variables and the briefing. Provider configuration is unchanged; browser use is explicit copying.

## 9. Local MCP boundary

- `MCPServer` owns listener, connections and deadlines on the main actor. The parser rejects malformed or duplicate headers, negative or overflowing lengths and transfer encoding.
- Limits: 16 KiB headers, 1 MiB body, 64 connections, 15 s to receive a request. The deadline is cancelled once parsed so browser tools can wait, bounded by their own timeouts.
- One request per connection; the connection closes after the response, also on client half-close. Results are MCP content blocks; screenshots return an image block plus caption.
- Host and Origin must name the exact loopback endpoint; native clients may omit Origin. No wildcard CORS. Tool calls need a managed-session URL; recruit operations check the orchestrator role. Diagnostic GET endpoints stay local and readable.
- Session UUIDs identify callers and are **not credentials**: other local processes can read diagnostics and impersonate sessions. This is a trusted-local-machine boundary with no remote access.
- Transport: JSON over HTTP/1.1 with Content-Length. SSE, batching, chunked bodies and pipelining are unsupported.
