# Decisions

## 2026-10-22 — Private browsers for agents, no automatic broadcasts

Give every CLI session its own WebKit browser inside AgentDeck, exposed through `browser_*` MCP tools, instead of
letting agents drive the user's Chrome. Alternatives: a dedicated Chrome profile per session (only Claude Code's
extension could use it, extension install per profile, windows outside AgentDeck) or both. The built-in browser
works for every CLI, keeps all agent browsing inside AgentDeck and isolates agents from the user and from each
other with per-session data stores. Consequence: capability is narrower than a full extension (no console or
network inspection yet); hidden tabs are parked in-window and occlusion detection is disabled via a private
WebKit selector, guarded by `responds(to:)`.

Remove the periodic status broadcast (`contextTick`, its settings and the interval). Every injected summary cost
each agent a turn and interrupted its work; with several sessions it was constant noise. Summaries now go out
only on explicit request or in the one-time start-up briefing.

Keep PTY output out of published state and lay out the stats strip on every pane: both were full-window
SwiftUI re-renders (per output chunk, and a terminal resize on every focus change) that showed up as typing lag
and focus flicker.

## 2026-10-22 — CLI tabs inside mini-windows

Keep sessions as the orchestration and process boundary; group them by a persisted pane UUID for presentation.
This preserves existing MCP callers and task ownership while allowing independent instances of one CLI in a
single mini-window. Legacy sessions retain separate windows. Persist the selected session per pane, synchronize
geometry across its tabs, and retain the native PTY views while hidden. New Tab shares the working directory
and worktree; it starts a fresh conversation without repeating the initial prompt or orchestrator role.
New Session remains available for separate panes. A referenced worktree cannot be deleted by closing one tab.

## 2026-10-22 — Shared browser sign-ins

Use one persistent AgentDeck WebKit profile by default for both existing and new browser panes. Store its UUID
in settings; preserve each pane's previous isolated UUID so Separate account can restore its old login data.
Do not merge authentication cookies or import Chrome profiles. Profile switches recreate only running browser
views, and removing a shared pane cannot delete the shared profile. This replaces the earlier per-pane isolation
default while retaining it as an explicit choice for separate accounts.

The startup collection now chooses one interface per provider (CLI preferred), superseding the original
all-CLI-and-browser collection described below.

## 2026-10-22 — Startup collection and shared skill folders

An empty launch seeds one pane per built-in agent CLI and browser preset; stored sessions are never duplicated. A setting can disable this, and removing the last pane does not immediately recreate it. Antigravity uses the official `agy` executable; Grok Build uses `grok`. Missing clients remain visible with setup links instead of being installed automatically.

Share selected skills through a generated catalog, local file paths and two MCP tools. This supports multiple CLI providers without rewriting their global settings or silently installing provider-specific plugins. Native slash-command registration is outside this integration. Browser chats receive instructions only through explicit copy/paste. Scan bounded directories off the main actor, deduplicate canonical paths and reject arbitrary paths in the read tool.

## 2026-10-22 — Correctness review and regression checks

Keep the current app structure and macOS deployment target. Enable complete concurrency checking without forcing a Swift 6 migration. Main-actor ownership gives the small local MCP listener one clear synchronization boundary. Bounded HTTP requests make this practical; it is not intended for high-throughput remote service use.

Use one request per HTTP connection to avoid response reordering and reentrant pipelined mutations. Clients reconnect normally. Native clients do not need CORS; reject foreign origins as required by the [MCP transport specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).

Capture subprocess streams in temporary files instead of sequential blocking pipes. Git work happens off the UI actor. This avoids stream deadlocks without adding a subprocess dependency; cancellation/timeouts for arbitrary long-running Git hooks remain a future improvement.

Run XCTest as a hostless bundle compiling the relevant production sources. Launching the ordinary app as a test host would load personal state and auto-start real agents. Tests use injected temporary storage, disposable repositories and browser profiles.

Swift guidance follows the [Swift API guidelines](https://www.swift.org/documentation/api-design-guidelines/) and [concurrency model](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html). The reusable `swift-best-practices` skill is installed in the user's Codex skills directory.
