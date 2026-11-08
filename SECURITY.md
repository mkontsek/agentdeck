# Security

AgentDeck trusts your user account and every process running under it. Its coordination API shares published tasks and context rather than private terminal transcripts. Separate-account browser profiles can isolate web sign-ins; shared profiles deliberately reuse them across agents. Agent CLIs are not sandboxed from one another or from your files.

## 1. Threat model

| Boundary | AgentDeck does | AgentDeck does not |
|---|---|---|
| MCP server | Binds to `127.0.0.1` only. Rejects a `Host` that is not the loopback endpoint and an `Origin` other than `http://127.0.0.1:<port>` / `http://localhost:<port>`, so web pages and DNS rebinding cannot call it. Bounded HTTP/1.1 parser: 16 KiB headers, 1 MiB body, 15 s deadline, 64 connections. | Authenticate callers. `/mcp/<uuid>` identifies a session; any local process that learns the UUID acts as it. `GET /` returns session names, directories and tasks to any local process. |
| Agent CLIs | Runs the command from Settings → CLI Profiles. Placeholders (`{cwd}`, `{sessionName}`, …) are inserted as literal shell data by Unicode scalar, never re-parsed. | Sandbox agents. **Built-in profiles pass `--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo` and `--always-approve`.** Agents run anything you can run. Edit the commands to remove the flags. |
| Messages between agents | Worker messages, results, handoff notices and context enter a durable inbox bound to the recipient session, profile and directory. Pending events attach to its next AgentDeck MCP result; explicit receipt is separate from task acceptance. Background updates never type, paste or submit terminal input. Only *Speaks MCP* profiles accept these events. | Verify peer intent or prove provider processing. Inbox text is published peer data, not authority to override the user. An idle CLI is not forced awake; a prompt-injected agent can still influence another agent. |
| Agent browsers | Each CLI controls its own browser tab. All shared ordinary/agent panes use one persistent AgentDeck profile; the user explicitly chose shared sign-ins. Separate account remains an opt-in isolated profile. External browser profiles are untouched. | Isolate a browser from the agent driving it. `browser_eval` runs arbitrary JavaScript, including on signed-in sites. |
| Files | Writes state, briefings and MCP configs under `~/Library/Application Support/AgentDeck/`. `read_skill` serves only regular `SKILL.md` files that resolve inside configured skill directories. Worktree deletion uses `git worktree remove` and refuses dirty trees. The log never records `browser_type` text, `browser_eval` scripts or URL query strings. | Encrypt anything. `state.json` holds session names, directories, tasks, the log and profile commands in plain text. Logs from versions before 0.1.11 may hold the first 40 characters of browser arguments; clear the log if you typed secrets through an agent browser. |

The app is ad-hoc signed, not sandboxed and without hardened runtime, because it spawns processes and binds a port. Build from source and read `project.yml` if that matters.

### Coordination and usage data

- New task completion and agent handoffs have user approval gates. MCP enforces task ownership, recipient-only handoff acceptance and participant/orchestrator access to handoff packages. Agents cannot approve their own gated work through MCP. Session UUIDs remain unauthenticated local identities, so these controls do not resist hostile processes running as the user.
- Handoffs contain explicitly published objectives/notes and supplied context/artifact references. They never automatically include terminal transcripts, browser contents, credentials or file contents. Published material is persisted in plaintext with task history.
- The separate `coordination-inbox.json` journal also stores published messages and receipt records in plaintext. Stable event IDs support deduplication; acknowledgment records receipt, not execution or completion. The bounded journal rejects new events when full instead of discarding accepted events.
- Restart checkpoints store provider conversation identifiers and file paths locally under `resume/`. The tracker inspects only managed process metadata/open-file names, not conversation bodies, and does not publish checkpoints through coordination tools. Browser panes persist their last URL alongside existing session settings.
- The usage panel reuses default CLI credentials only to request that provider's account usage. Claude Keychain access is noninteractive; Gemini credentials are read from its default OAuth file. The Codex CLI handles its own login through a short-lived app-server process. Tokens never appear in logs, task packages or state.
- Claude's serialized lookup temporarily disables legacy Keychain interaction and restores the previous process setting, alongside a noninteractive authentication context. If silent access is unavailable, usage stays unavailable. A five-minute memory-only cache avoids repeated reads; authentication failures invalidate it. No Keychain ACL or credential is changed.
- Automatic task workers inherit their parent's CLI command, permissions and directory/worktree. This is scheduling and UI isolation, not a security sandbox. Only own/unassigned tasks without pending handoffs can be delegated; workers cannot recursively delegate or recruit. Published task results retain the user's completion gate. Disable automatic subagents in Settings → Orchestration when desired.
- Provider HTTP requests reject redirects, use ephemeral URL sessions and do not borrow browser cookies. The panel never consumes earned resets, refreshes OAuth credentials, starts model turns or provisions projects. Samples remain in memory; stale and unavailable data are labeled.

## 2. Hardening checklist

- Remove the permission-bypass flags from the profiles you use, or run agents in Git worktrees (New Session → *Isolated git worktree*) so a mistake stays on a branch.
- Turn off *Speaks MCP* for any profile where typed text executes verbatim.
- Keep the MCP port on loopback; AgentDeck never listens elsewhere.
- Do not run AgentDeck while untrusted software runs under the same account.

## 3. Reporting

- Email martin@kontsek.io with a description and reproduction steps.
- Do not open a public issue for anything that endangers other users until a fix exists.
- No bug bounty. You get a reply and, if you want, credit in the release notes.
