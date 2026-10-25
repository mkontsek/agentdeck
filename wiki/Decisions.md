# Decisions

Each entry records what was chosen, the alternative, and the consequence. Newest first.

## 2026-10-25: Pre-publication security review

- A read-only second-model review (Codex) found four issues; all were fixed, none documented away.
- Shell placeholder escaping works on Unicode scalars: a quote plus combining mark is one `Character` and slipped past the grapheme-based check.
- Skill manifests must resolve to regular files inside a configured directory, so a repository symlink cannot publish an arbitrary readable file as instructions.
- Browser tool calls are logged without typed text, scripts or query strings, because the log lives in `state.json`.
- A companion browser can no longer switch to the shared profile, as the README had promised.
- Hardening: automated messages drop control characters, `browser_eval` has a 60 s deadline, `git worktree remove` gets `--`.
- Kept on purpose: unauthenticated loopback MCP (local processes are trusted, see SECURITY.md) and the `io.kontsek` bundle id.

## 2026-10-25: Browser downloads use the Mac Downloads folder

- WebKit picks no destination unless the app implements `WKDownloadDelegate`, so downloads go to a folder editable in Settings → General.
- The setting stores a path (`~/Downloads` by default) so an existing `state.json` gains it on decode. A fixed `~/Downloads` would ignore the folder a user wants for agent files.
- Names are forced to a single path component so a suggested filename cannot leave the folder.

## 2026-10-22: Private browsers for agents, no automatic broadcasts

- Every CLI session gets its own WebKit browser inside AgentDeck through `browser_*` MCP tools, instead of driving the user's Chrome.
- Alternatives: a Chrome profile per session (only Claude Code's extension could use it, per-profile extension installs, windows outside AgentDeck), or both.
- The built-in browser serves every CLI, keeps browsing inside AgentDeck and isolates agents from the user and each other with per-session data stores.
- Consequence: narrower than a full extension (no console or network inspection yet). Hidden tabs park in-window; occlusion detection is disabled via a private WebKit selector guarded by `responds(to:)`.
- The periodic status broadcast (`contextTick`, its settings and interval) is gone: each summary cost every agent a turn and became constant noise. Summaries go out only on request or in the start-up briefing.
- PTY output stays out of published state and the stats strip is laid out on every pane: both were full-window re-renders that showed as typing lag and focus flicker.

## 2026-10-22: CLI tabs inside mini-windows

- Sessions stay the orchestration and process boundary; a persisted pane UUID groups them for presentation. MCP callers and task ownership are unchanged; legacy sessions keep separate windows.
- The selected session persists per pane, geometry is shared across tabs, hidden PTY views are retained.
- New Tab shares directory and worktree and starts a fresh conversation without the initial prompt or orchestrator role. New Session still creates a separate pane. A referenced worktree cannot be deleted by closing one tab.

## 2026-10-22: Shared browser sign-ins

- One persistent AgentDeck WebKit profile is the default for existing and new browser panes; its UUID lives in settings.
- Each pane keeps its previous isolated UUID so Separate account restores old login data. No cookies are merged and no Chrome profile is imported.
- Profile switches recreate only running views; removing a shared pane cannot delete the shared profile. Per-pane isolation stays an explicit choice.
- The startup collection now picks one interface per provider, CLI preferred, superseding the all-CLI-and-browser collection below.

## 2026-10-22: Startup collection and shared skill folders

- An empty launch seeds one pane per built-in CLI and browser preset; stored sessions are never duplicated. A setting disables it; removing the last pane does not recreate it.
- Antigravity uses the official `agy` executable, Grok Build uses `grok`. Missing clients stay visible with setup links instead of being installed.
- Skills are shared through a generated catalog, local paths and two MCP tools, without rewriting provider settings or installing plugins. Native slash commands are out of scope; browser chats get instructions only by copy and paste.
- Scanning is bounded, off the main actor, deduplicated by canonical path, and the read tool rejects arbitrary paths.

## 2026-10-22: Correctness review and regression checks

- Keep the app structure and macOS target; enable complete concurrency checking without a Swift 6 migration. Main-actor ownership gives the loopback MCP listener one synchronization boundary; bounded requests make that practical. It is not a high-throughput remote service.
- One request per connection avoids response reordering and reentrant pipelined mutations; clients reconnect. Foreign origins are rejected per the [MCP transport specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports); native clients need no CORS.
- Subprocess streams are captured in temporary files, Git runs off the UI actor. Cancellation and timeouts for long-running Git hooks remain future work.
- XCTest runs as a hostless bundle compiling the relevant sources; the app as test host would load personal state and auto-start real agents. Tests use temporary storage, disposable repositories and browser profiles.
- Swift guidance: the [API guidelines](https://www.swift.org/documentation/api-design-guidelines/) and [concurrency model](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html); the `swift-best-practices` skill lives in the user's Codex skills directory.
