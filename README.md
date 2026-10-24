# AgentDeck

A native macOS app (Swift + SwiftUI) that acts as a visual orchestration layer for several AI agents at once.
It launches and owns real CLI agents (Claude Code, Codex, Gemini CLI, Antigravity, Grok, plain shells, …) in embedded
PTY terminals, opens browser panes with shared sign-ins for web models (ChatGPT, Claude.ai, Gemini, Grok, …), and gives
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
make test       # regression tests with isolated state, local PTYs and WebKit
make format     # Xcode swift-format
make lint       # strict style check
make check      # lint + tests + Release build
make clean
```

`make` passes `-skipPackagePluginValidation` because SwiftTerm ships a build-tool plugin. The app is ad-hoc signed and
not sandboxed (it has to spawn processes and bind a local port).

Architecture, verification coverage, and remaining manual checks are documented in the [wiki](wiki/Home.md).
Lint/format require an Xcode toolchain containing `swift-format`.

## Sessions

On launch, an empty canvas opens one interface per provider: Claude Code, Codex, Antigravity,
Grok Build, and Perplexity. Gemini CLI is the Google fallback when the Antigravity profile is absent;
browser presets are fallbacks when their provider's CLI profile is absent. All browser presets and
Gemini CLI remain available through New Session.
Existing sessions are restored without duplicating the collection. Missing CLIs show installation links;
AgentDeck does not install tools or sign in for you. Settings → General controls this behavior and the
default CLI directory (`~/gitrepos`). Closing the last session leaves the centered empty canvas until
the next launch or until you click **Open default sessions**.

New panes default to Compact (440×300) with 11 pt terminal text, and new main windows start at
1400×900. Saved size/font choices are preserved. The first click inside an inactive pane focuses it;
subsequent clicks interact with its terminal or browser. AgentDeck's icon and name appear in the toolbar.

**New Session (⌘N)** creates either:

- a **CLI session** — pick a CLI profile, a working directory, optionally an isolated **git worktree**
  (created at `<worktree root>/<repo>/<session-slug>` on branch `agentdeck/<session-slug>`), a first prompt, and
  whether the session is the **Orchestrator**;
- a **browser session** — ChatGPT, Claude.ai, Gemini, Grok, Perplexity or any URL. **Shared AgentDeck** is the
  default profile: sign in once per service, then other shared panes reuse its cookies and site storage.
  Sign-ins persist across restarts; signing out affects other shared panes for that service. Choose
  **Separate account** when creating a pane or in its inspector for an independent login. Changing a
  running pane's profile reloads that pane; stopped panes stay stopped.

Existing browser panes move to the shared profile on upgrade. Their previous individual data is retained
and can be accessed by choosing **Separate account**. It is not merged into the shared profile, and Chrome
sign-ins are not imported. Removing a shared pane retains the shared profile, even when it is the last pane.

Sessions persist across restarts (`~/Library/Application Support/AgentDeck/state.json`) and are relaunched at start
unless "Start at launch" is off. A session that exits shows a Restart overlay; the sidebar and pane menus offer
Restart / Stop / Remove (optionally deleting the worktree or browser profile).
Worktree creation failure cancels session creation. Deletion refuses dirty worktrees and retains the session so
uncommitted files can be recovered. Unreadable saved state is preserved and reported instead of overwritten.

Each CLI mini-window has a tab strip. Click **+** or press **⌘T** to start another instance of that CLI
in the same directory. Tabs have independent terminals, output, status, tasks and MCP identities; hidden tabs
keep running. Click a tab or select its session in the sidebar to reveal it. **⇧⌘[ / ⇧⌘]** cycles tabs,
and a tab's **×** closes just that session. Closing the last tab removes its mini-window.
Position, size, tab order and selected tabs persist across launches, including in Grid and maximized views.
**⌘N** still creates a separate mini-window. New tabs inherit font and launch preferences, but do not repeat
the original prompt or inherit the orchestrator role. Tabs opened from a worktree share that worktree;
remove other sessions using it before requesting worktree deletion.

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
| Move | Canvas: drag a pane by its header; it follows the pointer and comes to the front; positions persist |
| Tidy | ⌥⌘T or the toolbar button re-packs panes at their current sizes, with Claude CLI first and Codex second |
| Fill Canvas | ⌥⌘F or **Fill Canvas** resizes and arranges panes into balanced rows using the visible canvas; very small canvases scroll to preserve readable minimum sizes |
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
| `AGENTDECK_BRIEFING` | path to the session's Markdown briefing (identity, tools, board, skills) |

How the built-in profiles connect:

| Profile | Launch command | MCP |
|---|---|---|
| Claude Code | `claude --dangerously-skip-permissions --mcp-config "{mcpConfigPath}" --append-system-prompt-file "{briefingPath}"` | automatic |
| Codex | `codex --dangerously-bypass-approvals-and-sandbox -c 'mcp_servers.agentdeck.url="{mcpUrl}"'` | automatic |
| Gemini CLI | `gemini --yolo` | once: `gemini mcp add -t http -s user agentdeck $AGENTDECK_MCP_URL` |
| Antigravity | `agy --dangerously-skip-permissions` | configure a remote server in `/mcp` using the session MCP URL |
| Grok Build | `grok --always-approve` | configure with `grok mcp` using `$AGENTDECK_MCP_URL` |
| Plain shell | `exec $SHELL -l` | none (no briefings are injected into shells) |

Agent profiles bypass tool permission prompts by default. Codex also bypasses its sandbox. Edit the commands
in Settings → CLI Profiles to change this. A one-time upgrade updates unchanged older built-in commands;
custom commands and subsequent edits are preserved. Running sessions pick up changes when restarted.

### Continuing the last conversation

Sessions reopen their last conversation by default. When a session starts and the provider has a conversation
for the session's directory, AgentDeck runs the profile's *resume command* instead of its command:

| Profile | Resume command | Detected from |
|---|---|---|
| Claude Code | `claude --continue …` | `~/.claude/projects/<encoded directory>/*.jsonl` |
| Codex | `codex resume --last …` | `~/.codex/sessions/**/rollout-*.jsonl` whose `cwd` matches |
| Gemini CLI | `gemini --yolo --resume latest` | `~/.gemini/tmp/<directory name>/chats/` |

A directory without a prior conversation starts fresh. Turn this off per session with the inspector's
"Continue last conversation on start" or at creation time; clear a profile's resume command to disable it for
every session using that profile. A resumed session is not briefed again and does not receive its first prompt
again. The focused session and pane tabs are restored at launch regardless.

`GET http://127.0.0.1:4820/` returns a JSON snapshot of sessions and tasks for debugging.
Tool calls require a known session endpoint. The server validates Host and Origin and rejects foreign web origins.
It trusts local processes: session IDs provide identity, not authentication against hostile local applications.

### Tools

| Tool | Purpose |
|---|---|
| `whoami` | the caller's own session record |
| `list_sessions` | every managed session with status, directory, pending question, open task ids |
| `read_board` | the task board (optional `status` filter) |
| `list_skills` / `read_skill` | list enabled local skills and read their instructions by exact skill ID |
| `create_task` | add a task (`title`, `description`, `owner`, `status`, `notes`) |
| `update_task` | claim (`owner: "me"`), change `status`, append `notes`, edit title/description |
| `handoff` | assign a task to another session and type a handoff message into its input (queued until it is idle) |
| `send_message` | type a free-form single-line note into another CLI session |
| `log` | append to the orchestration log |
| `recruit_session` / `recruit_status` | **Orchestrator only** — ask the user to approve a new session (approve/deny in the sidebar) |
| `browser_navigate` / `browser_read` / `browser_click` / `browser_type` / `browser_screenshot` / `browser_eval` | **CLI sessions only** — drive the caller's private browser (see below) |

Sessions are addressed by name, id, id prefix or `"me"`.

### Private browsers for agents

Agents never use your own browser. The first `browser_*` call from a CLI session opens a WebKit tab beside its
terminal (named `<session> browser`, globe icon) with its own isolated website data store, so sessions cannot see
each other's cookies or sign-ins either. The tab is created without stealing focus; click it to watch or help, for
example to sign in once. Removing the CLI session removes its browser and deletes the profile.

- `browser_navigate` loads a URL and waits for it; `browser_read` returns the visible text, links or HTML;
  `browser_click` targets a CSS selector or visible text; `browser_type` fills a field and can press Enter;
  `browser_eval` runs JavaScript; `browser_screenshot` returns a PNG.
- A hidden tab keeps working: it is parked off-screen inside the main window while a tool runs, and occlusion
  detection is disabled so it keeps rendering while your own windows cover AgentDeck. Screenshots still need the
  AgentDeck window to be on screen somewhere.

### How agents learn about each other

- **Briefing.** Before a CLI session launches, AgentDeck writes `~/Library/Application Support/AgentDeck/briefing/<id>.md`:
  who it is, where it runs, which tools exist, the current board and the skill catalog. Claude Code loads it as
  an appended system prompt (`--append-system-prompt-file "{briefingPath}"`), so nothing appears in the
  terminal. Profiles without `{briefingPath}` in their command are typed one line the first time they go idle:
  `[AgentDeck] Read your briefing at <path> before working.` — followed by the session's "first prompt" if you
  set one. `AGENTDECK_BRIEFING` also points at the file.
- **Status summaries** are never broadcast automatically; each one costs the agent a turn. "Inject Context Now"
  (Session menu, pane menu or inspector) sends the focused session one line like
  `[AgentDeck status] Sessions: Claude A (idle, you), Codex B (working). Open tasks: 2 — #3 "Fix login" (in-progress, Codex B)…`.
  The per-session "Include status summary in start-up briefing" toggle only affects the briefing above.
- **Handoffs** arrive as `[AgentDeck handoff from X] Task #N: … update_task(task_id=N, status=in-progress, owner=me)`.
- **Inject Note (⇧⌘I)** types anything you want into the focused session as if you had typed it.

Injected text is typed into the PTY followed by Enter after the profile's *submit delay*; newlines are collapsed
to one line. If the target is not idle the message is queued and delivered on its next idle tick.
Stopped sessions reject messages. Profiles with *Speaks MCP* off reject automated messages; their task handoffs
are board assignments only. Explicit user-entered notes and first prompts remain available.

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

`{mcpUrl}` `{mcpConfigPath}` `{briefingPath}` `{sessionId}` `{sessionName}` `{cwd}`

A profile may also have a *resume command* with the same placeholders; see "Continuing the last conversation".
Include `{briefingPath}` in the command when the CLI can take a system-prompt file, and the briefing is never typed.

Placeholders are inserted as literal data in ordinary unquoted, single-quoted and double-quoted arguments.
Use environment variables for advanced shell constructs such as here-documents and nested command substitutions.

Set *Submit delay* if the CLI needs a pause between the typed text and Enter (Ink-based TUIs want ~150 ms), and turn
off *Speaks MCP* for tools that should never receive briefings (anything where typed text would be executed).
Profiles are stored in `state.json`; built-ins are re-added if missing.

Example for a hypothetical CLI that takes an MCP URL flag:

```
my-agent --mcp-http agentdeck={mcpUrl} --name "{sessionName}"
```

## Shared skill directories

Settings → **Skills** loads skill folders or repositories containing `.agents/skills`, `.claude/skills`,
`.codex/skills`, `.gemini/skills`, or `skills`. The defaults are `~/gitrepos` and `~/.codex/skills`, so shared
repository conventions and the Swift best practices skill are included. You can add/remove folders,
enable individual skills, preview instructions, open their source files, and reload after edits.

AgentDeck writes a catalog at `~/Library/Application Support/AgentDeck/skills/catalog.md`, exports
`AGENTDECK_SKILLS_FILE` and JSON `AGENTDECK_SKILL_DIRECTORIES`, and points CLI agents to relevant skill
files in their briefing file. Connected MCP clients can call `list_skills` and `read_skill`.
This shares instructions without modifying provider configuration or copying skills into repositories;
it does not register provider-native slash commands. For an already-running agent, use **Use in focused CLI**.
For browser chats, use **Copy for browser** and paste the instructions yourself. A browser chat cannot
read your local skill scripts merely because the catalog exists.

## Image generation

Codex interactive sessions support image generation when the account and tool configuration enable it;
describe the desired image or request `$imagegen`. Antigravity also provides a generative image tool.
AgentDeck hosts the CLI and browser interfaces; availability and usage limits belong to each provider.
A Gemini browser subscription does not, by itself, configure an API key or another client's tools.
See [Codex image generation](https://learn.chatgpt.com/docs/image-generation) and
[Antigravity models and tools](https://www.antigravity.google/docs/models/).

## Files

| Path | Contents |
|---|---|
| `Sources/App` | app entry, menu commands |
| `Sources/Models` | sessions, tasks, settings, CLI profiles |
| `Sources/Store/AppStore.swift` | the single source of truth: lifecycle, persistence, status loop, injection, handoffs, recruits |
| `Sources/Terminal` | SwiftTerm PTY host and SwiftUI wrapper |
| `Sources/Browser` | isolated WKWebView host and pane, agent browser tools and their page scripts |
| `Sources/MCP` | loopback HTTP server, JSON-RPC routing, tool definitions |
| `Sources/Services` | status heuristics, git worktree helpers |
| `Sources/Views` | sidebar, pane grid, board, log, inspector, sheets, settings |
| `scripts/make-icon.swift` | renders the app icon; `make icon` rebuilds `Resources/AppIcon.icns` |
| `~/Library/Application Support/AgentDeck/` | `state.json`, per-session `mcp/*.json` |
| `~/.agentdeck/worktrees/` | default worktree root (Settings) |

## Known limitations

- Status detection is heuristic; a CLI with unusual prompts may show Working while it waits. Add patterns in
  `StatusHeuristics.swift`.
- Injection types a single line. Multi-line notes are collapsed.
- The MCP transport answers with plain JSON (no SSE stream); `GET /mcp` returns 405, which clients handle.
- Requests use HTTP/1.1 with Content-Length; chunked requests and pipelining are unsupported. Each response closes
  its connection. Request limits are 16 KiB headers and 1 MiB bodies, with a 15-second connection deadline.
- An orchestrator's recruit request shows as an orange "approval" badge in the toolbar when the sidebar is hidden.
- Some providers restrict embedded sign-in. Shared profiles reuse successful AgentDeck sign-ins but do not bypass
  provider restrictions or import an existing Chrome session.
- Browser sessions receive handoffs on the board only; nothing is typed into web UIs (no DOM automation by design).
- A nested launch strips `CLAUDE*`/`CODEX_*` variables from the child environment so Claude Code does not refuse to
  start inside another Claude Code session.

## License

MIT
