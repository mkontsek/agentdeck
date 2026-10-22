# AgentDeck

A native macOS app (Swift + SwiftUI) that acts as a visual orchestration layer for several AI agents at once.
It launches and owns real CLI agents (Claude Code, Codex, Gemini CLI, OpenCode, plain shells, …) in embedded
PTY terminals, opens isolated browser profiles for web models (ChatGPT, Claude.ai, Gemini, Grok, …), and gives
all of them a shared task board plus an MCP server so they can coordinate **without peering inside each other**.

Subagents that a CLI spawns internally stay inside their parent pane. AgentDeck only manages sessions it created.

```
┌ ⊞ +  AgentDeck            grid|canvas  Normal  A ──●── 13        ☾ ((·)) ▭ ▯ ┐
│ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │
│ · ┌ ● Claude A  working ─ ~/repo ─ 13 ⋯┐ · · ┌ ● ChatGPT  idle ─────────⋯┐ · │
│ · │ working 42s · up 12m · Opus 4 · ctx │ · · │ (isolated WKWebView)       │ · │
│ · │ 31% · 2 open: #3 #5 · 13 pt         │ · · │                            │ · │
│ · │  (PTY terminal)                      │ · · └────────────────────────────┘ · │
│ · └──────────────────────────────────────┘ · · · · ┌ ● Codex B  idle ─────⋯┐ · │
│ · · · · · · · · · · · · · · · · · · · · · · · · ·  │  (PTY terminal)        │ · │
│ · · · · · · · · · · · · · · · · · · · · · · · · ·  └────────────────────────┘ · │
└───────────────────────────────────────────────────────────────────────────────┘
   Sessions sidebar (⌥⌘S), task board + log (⌥⌘B) and inspector (⌥⌘I) slide in on demand.
```

## Requirements

- macOS 14 or newer (isolated `WKWebsiteDataStore(forIdentifier:)` profiles need 14+)
- Xcode 16 or newer with command line tools
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

The only package dependency is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (PTY + terminal emulation).
It is resolved by Xcode on first build.

## Build and run

```sh
make run        # generate the Xcode project, build Release, open the app
make install    # copy the built app to /Applications
make build CONFIG=Debug
make clean
```

`make` passes `-skipPackagePluginValidation` because SwiftTerm ships a build-tool plugin. The app is ad-hoc signed and
not sandboxed (it has to spawn processes and bind a local port).

## Sessions

**New Session (⌘N)** creates either:

- a **CLI session** — pick a CLI profile, a working directory, optionally an isolated **git worktree**
  (created at `<worktree root>/<repo>/<session-slug>` on branch `agentdeck/<session-slug>`), a first prompt, and
  whether the session is the **Orchestrator**;
- a **browser session** — ChatGPT, Claude.ai, Gemini, Grok, Perplexity or any URL. Each one has its own persistent
  website data store, so cookies, logins and tabs never collide.

Sessions persist across restarts (`~/Library/Application Support/AgentDeck/state.json`) and are relaunched at start
unless "Start at launch" is off. A session that exits shows a Restart overlay; the sidebar and pane menus offer
Restart / Stop / Remove (optionally deleting the worktree or browser profile).

### Status badges

| Badge | Meaning (CLI sessions) |
|---|---|
| Starting | process launched less than 2 s ago |
| Working | output in the last few seconds, or a busy indicator ("esc to interrupt", spinner, "Thinking") is on screen |
| Idle | no output for *Idle after quiet* seconds and no busy indicator |
| Waiting for user | a prompt such as `(y/n)`, "Do you want to…", "Enter to confirm", "1. Yes" is on screen |
| Stalled | a busy indicator is on screen but there has been no output for *Stalled after* seconds |
| Quota warning | "rate limit", "usage limit", "quota", "429", "overloaded" on screen |
| Error / Exited | process ended with non-zero / zero exit code |

Detection is heuristic and reads only the **visible** terminal rows, so a prompt that scrolled away no longer counts.
Programs that emit OSC 7501 program-status records (supported by SwiftTerm) override the heuristics. Thresholds and
patterns live in Settings → Orchestration and `Sources/Services/StatusHeuristics.swift`. Browser sessions are
Working while loading and Idle otherwise.

## Font and pane sizing

| Control | Where |
|---|---|
| Global font size | toolbar slider, Settings → General (affects every CLI pane without an override) |
| Per-pane font | `−` `13` `+` in the pane header, inspector, or ⌘+ / ⌘= / ⌘− / ⌘0 on the focused pane (⌘0 = back to global) |
| Layout | toolbar: **Canvas** (default) makes every pane a movable mini-window; **Grid** tiles panes evenly into N columns (stepper) |
| Move | Canvas: drag a pane by its header; it snaps to an 8 pt grid and comes to the front; positions persist |
| Tidy | ⌥⌘T or the toolbar button re-packs the mini-windows left to right at their current sizes |
| Pane presets | Compact / Normal / Large: toolbar (default for all), pane menu, inspector, View → Pane Size |
| Drag to resize | Canvas: drag the grip at a pane's bottom-right corner; double-click it to reset |
| Maximize | ⇧⌘M or pane menu; ⇧⌘M again restores |
| Side panels | all collapsed by default: sidebar ⌥⌘S, inspector ⌥⌘I, task board + log ⌥⌘B, or the toolbar toggles |
| Theme | ⌥⌘D flips light/dark; System / Light / Dark in View → Appearance or Settings. Terminals and web panes follow |

### Focused pane stats

The focused mini-window shows a stats strip under its header: status with time in that state, uptime, the CLI,
model name and context usage, git worktree branch, open tasks, the pending question, program status (OSC 7501)
and the effective font size. Model name and context (for example `Opus 4.1` or `63% context left`) are scraped
from the CLI's own status line in the bottom rows of its screen, so they appear only when the CLI prints them;
patterns live in `StatusHeuristics.modelStats`. Browser panes show page title and host instead. The inspector
(⌥⌘I) shows the same data plus controls.

Every change applies immediately and is saved.

## Orchestration

### MCP server

AgentDeck runs a streamable-HTTP MCP server on `http://127.0.0.1:4820` (port in Settings). Each session gets its own
endpoint so the server knows who is calling:

```
http://127.0.0.1:4820/mcp/<session-id>
```

Every CLI session is launched with these environment variables and files:

| | |
|---|---|
| `AGENTDECK_SESSION_ID`, `AGENTDECK_SESSION_NAME` | identity |
| `AGENTDECK_MCP_URL` | the session's endpoint |
| `AGENTDECK_MCP_CONFIG` | path to a JSON file `{"mcpServers":{"agentdeck":{"type":"http","url":…}}}` |

How the built-in profiles connect:

| Profile | Launch command | MCP |
|---|---|---|
| Claude Code | `claude --mcp-config "{mcpConfigPath}"` | automatic |
| Codex | `codex -c 'mcp_servers.agentdeck.url="{mcpUrl}"'` | automatic |
| Gemini CLI | `gemini` | once: `gemini mcp add -t http -s user agentdeck $AGENTDECK_MCP_URL` |
| OpenCode | `opencode` | add `{"mcp":{"agentdeck":{"type":"remote","url":"…"}}}` to `opencode.json` |
| Grok CLI | `grok` | per its docs, URL in `$AGENTDECK_MCP_URL` |
| Plain shell | `exec $SHELL -l` | none (no briefings are injected into shells) |

`GET http://127.0.0.1:4820/` returns a JSON snapshot of sessions and tasks for debugging.

### Tools

| Tool | Purpose |
|---|---|
| `whoami` | the caller's own session record |
| `list_sessions` | every managed session with status, directory, pending question, open task ids |
| `read_board` | the task board (optional `status` filter) |
| `create_task` | add a task (`title`, `description`, `owner`, `status`, `notes`) |
| `update_task` | claim (`owner: "me"`), change `status`, append `notes`, edit title/description |
| `handoff` | assign a task to another session and type a handoff message into its input (queued until it is idle) |
| `send_message` | type a free-form single-line note into another CLI session |
| `log` | append to the orchestration log |
| `recruit_session` / `recruit_status` | **Orchestrator only** — ask the user to approve a new session (approve/deny in the sidebar) |

Sessions are addressed by name, id, id prefix or `"me"`.

### How agents learn about each other

- **Briefing.** The first time a CLI session goes idle, AgentDeck types one message into it: who it is, where it
  runs, which tools exist, and the current board — followed by the session's "first prompt" if you set one.
- **Status summaries.** While a session is idle, and only when the board or session list changed since the last
  summary (and at most once per *Minimum interval*), it receives one line like
  `[AgentDeck status] Sessions: Claude A (idle, you), Codex B (working). Open tasks: 2 — #3 "Fix login" (in-progress, Codex B)…`.
  Each summary costs the agent a turn, so the interval defaults to 5 minutes. Toggle per session in the inspector
  or globally in Settings. "Inject Context Now" sends one on demand.
- **Handoffs** arrive as `[AgentDeck handoff from X] Task #N: … update_task(task_id=N, status=in-progress, owner=me)`.
- **Inject Note (⇧⌘I)** types anything you want into the focused session as if you had typed it.

Injected text is typed into the PTY followed by Enter after the profile's *submit delay*; newlines are collapsed
to one line. If the target is not idle the message is queued and delivered on its next idle tick.

### A typical agent workflow

```
read_board                     → see open work
update_task(task_id=4, owner="me", status="in-progress")
… do the work …
update_task(task_id=4, status="done", notes="PR #12 opened")
handoff(target_session="Codex B", title="Review PR #12", note="focus on the auth middleware")
```

An Orchestrator session can additionally `recruit_session(name="Tests", cli_profile="codex", use_worktree=true,
initial_prompt="Run the test suite and report failures to the board")`; the request appears in the sidebar for approval.

## Adding a new CLI type

Settings → **CLI Profiles** → `+`. A profile is a zsh snippet run as `zsh -l -i -c "<command>"` in the session's
directory, with these placeholders:

`{mcpUrl}` `{mcpConfigPath}` `{sessionId}` `{sessionName}` `{cwd}`

Set *Submit delay* if the CLI needs a pause between the typed text and Enter (Ink-based TUIs want ~150 ms), and turn
off *Speaks MCP* for tools that should never receive briefings (anything where typed text would be executed).
Profiles are stored in `state.json`; built-ins are re-added if missing.

Example for a hypothetical CLI that takes an MCP URL flag:

```
my-agent --mcp-http agentdeck={mcpUrl} --name "{sessionName}"
```

## Files

| Path | Contents |
|---|---|
| `Sources/App` | app entry, menu commands |
| `Sources/Models` | sessions, tasks, settings, CLI profiles |
| `Sources/Store/AppStore.swift` | the single source of truth: lifecycle, persistence, status loop, injection, handoffs, recruits |
| `Sources/Terminal` | SwiftTerm PTY host and SwiftUI wrapper |
| `Sources/Browser` | isolated WKWebView host and pane |
| `Sources/MCP` | loopback HTTP server, JSON-RPC routing, tool definitions |
| `Sources/Services` | status heuristics, git worktree helpers |
| `Sources/Views` | sidebar, pane grid, board, log, inspector, sheets, settings |
| `~/Library/Application Support/AgentDeck/` | `state.json`, per-session `mcp/*.json` |
| `~/.agentdeck/worktrees/` | default worktree root (Settings) |

## Known limitations

- Status detection is heuristic; a CLI with unusual prompts may show Working while it waits. Add patterns in
  `StatusHeuristics.swift`.
- Injection types a single line. Multi-line notes are collapsed.
- The MCP transport answers with plain JSON (no SSE stream); `GET /mcp` returns 405, which clients handle.
- An orchestrator's recruit request shows as an orange "approval" badge in the toolbar when the sidebar is hidden.
- Google sign-in sometimes refuses embedded web views even with the Safari user agent used here; sign in to Gemini
  in a Chrome profile if that happens.
- Browser sessions receive handoffs on the board only; nothing is typed into web UIs (no DOM automation by design).
- A nested launch strips `CLAUDE*`/`CODEX_*` variables from the child environment so Claude Code does not refuse to
  start inside another Claude Code session.

## License

MIT
