# Security

AgentDeck launches AI coding agents on your Mac and lets them coordinate through a local HTTP server. Read this
before running it on a machine you care about.

## Threat model

AgentDeck **trusts your user account and every process running under it**. It does not try to protect you from
software that is already running as you.

| Boundary | What AgentDeck does | What it does not do |
|---|---|---|
| MCP server | Binds to `127.0.0.1` only. Rejects requests whose `Host` is not the loopback endpoint and web requests whose `Origin` is not `http://127.0.0.1:<port>` / `http://localhost:<port>`, so browser pages and DNS-rebinding attacks cannot call it. Bounded HTTP/1.1 parser (16 KiB headers, 1 MiB body, 15 s deadline, 64 connections). | Authenticate callers. A session's endpoint `/mcp/<uuid>` identifies the session; any local process that learns the UUID can act as that session. `GET /` returns a status snapshot (session names, directories, tasks) to any local process. |
| Agent CLIs | Runs the command you configure in Settings → CLI Profiles. Placeholders (`{cwd}`, `{sessionName}`, …) are inserted as literal shell data, not re-parsed. | Sandbox the agents. **The built-in profiles pass `--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo` and `--always-approve`.** Agents can run any command you can run. Edit the profile commands to remove these flags if that is not what you want. |
| Messages between agents | `send_message` and `handoff` type text into another session's terminal. Only profiles marked *Speaks MCP* accept automated messages; plain shells never do. | Verify intent. A prompt-injected agent can type instructions into another agent. Treat every session as having the same authority as the least careful one. |
| Agent browsers | Each CLI session's browser uses its own `WKWebsiteDataStore`, so sessions cannot read each other's cookies or sign-ins, and agents never touch your own browser. Shared browser panes for web chats use one profile per service by design. | Isolate the browser from the agent that drives it. `browser_eval` runs arbitrary JavaScript in that agent's own browser, including on sites where it is signed in. |
| Files | Writes state, briefings and MCP configs under `~/Library/Application Support/AgentDeck/`. `read_skill` only serves regular `SKILL.md` files that resolve inside the skill directories you configured. Worktree deletion goes through `git worktree remove` and refuses dirty trees. The orchestration log never records text typed by `browser_type`, `browser_eval` scripts or URL query strings. | Encrypt anything. `state.json` contains session names, directories, task text, the orchestration log and your CLI profile commands in plain text. Logs written by versions before 0.1.11 may contain the first 40 characters of browser arguments; clear the log if you typed secrets through an agent's browser. |

The app is ad-hoc signed, not sandboxed and does not use the hardened runtime, because it has to spawn processes
and bind a port. Build it from source and read `project.yml` if that matters to you.

## Hardening checklist

- Remove the permission-bypass flags from the profile commands you use, or run agents in Git worktrees
  (New Session → *Isolated git worktree*) so a mistake is contained to a branch.
- Turn off *Speaks MCP* for any profile where typed text would be executed verbatim.
- Keep the MCP port on the default loopback binding; AgentDeck never listens on other interfaces.
- Do not run AgentDeck while untrusted software runs under the same user account.

## Reporting a vulnerability

Email martin@kontsek.io with a description and reproduction steps. Please do not open a public issue for
anything that could put other users at risk until a fix is available. There is no bug bounty; you will get a
reply and credit in the release notes if you want it.
