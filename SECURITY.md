# Security

AgentDeck trusts your user account and every process running under it; it protects you from the web and from agents reading each other, not from software already running as you.

## 1. Threat model

| Boundary | AgentDeck does | AgentDeck does not |
|---|---|---|
| MCP server | Binds to `127.0.0.1` only. Rejects a `Host` that is not the loopback endpoint and an `Origin` other than `http://127.0.0.1:<port>` / `http://localhost:<port>`, so web pages and DNS rebinding cannot call it. Bounded HTTP/1.1 parser: 16 KiB headers, 1 MiB body, 15 s deadline, 64 connections. | Authenticate callers. `/mcp/<uuid>` identifies a session; any local process that learns the UUID acts as it. `GET /` returns session names, directories and tasks to any local process. |
| Agent CLIs | Runs the command from Settings → CLI Profiles. Placeholders (`{cwd}`, `{sessionName}`, …) are inserted as literal shell data by Unicode scalar, never re-parsed. | Sandbox agents. **Built-in profiles pass `--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo` and `--always-approve`.** Agents run anything you can run. Edit the commands to remove the flags. |
| Messages between agents | `send_message` and `handoff` type text into another terminal. Only *Speaks MCP* profiles accept automated messages; plain shells never do. Control characters are dropped. | Verify intent. A prompt-injected agent can instruct another agent. Every session has the authority of the least careful one. |
| Agent browsers | Each CLI session's browser has its own `WKWebsiteDataStore`, locked to the isolated profile; agents never touch your browser or each other's cookies. Shared panes for web chats use one profile per service by design. | Isolate a browser from the agent driving it. `browser_eval` runs arbitrary JavaScript, including on signed-in sites. |
| Files | Writes state, briefings and MCP configs under `~/Library/Application Support/AgentDeck/`. `read_skill` serves only regular `SKILL.md` files that resolve inside configured skill directories. Worktree deletion uses `git worktree remove` and refuses dirty trees. The log never records `browser_type` text, `browser_eval` scripts or URL query strings. | Encrypt anything. `state.json` holds session names, directories, tasks, the log and profile commands in plain text. Logs from versions before 0.1.11 may hold the first 40 characters of browser arguments; clear the log if you typed secrets through an agent browser. |

The app is ad-hoc signed, not sandboxed and without hardened runtime, because it spawns processes and binds a port. Build from source and read `project.yml` if that matters.

## 2. Hardening checklist

- Remove the permission-bypass flags from the profiles you use, or run agents in Git worktrees (New Session → *Isolated git worktree*) so a mistake stays on a branch.
- Turn off *Speaks MCP* for any profile where typed text executes verbatim.
- Keep the MCP port on loopback; AgentDeck never listens elsewhere.
- Do not run AgentDeck while untrusted software runs under the same account.

## 3. Reporting

- Email martin@kontsek.io with a description and reproduction steps.
- Do not open a public issue for anything that endangers other users until a fix exists.
- No bug bounty. You get a reply and, if you want, credit in the release notes.
