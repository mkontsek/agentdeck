# Coordination and usage

The Work workspace is the app's front door. Sessions retains the terminal/browser desk. The CLI usage mini-window can be moved, resized, hidden and reopened with ⌥⌘U. In a session mini-window’s header menu, **Remove mini-window** closes all its tabs, even when a browser is selected. A tab’s **×** closes only that tab. Browser sign-ins, worktrees and task history are retained; independent child windows remain open. Pending native continuations must be cancelled or reconciled before the window can close.

## Handoff contract

1. The owner or orchestrator publishes the task objective, notes, summary, constraints, artifact references, verification and next action.
2. The user approves an agent-prepared package by default. User-composed packages are approved on send.
3. AgentDeck accepts a short notification into the recipient’s separate durable inbox. A stopped recipient does not lose the package.
4. The recipient reads `read_handoffs` and calls `accept_handoff`. Only acceptance transfers ownership; a stale task revision requires a new package.
5. The reviewer requests completion. New tasks enter `awaiting-approval` until the user approves them.

Open delivery states and all handoff events persist. “Delivered” means inbox acceptance, not provider processing. Interrupted delivery becomes retryable after restart; notifications are never interpreted as proof of acceptance. The board supports cancellation and explicit notification retry.

## Worker inbox and draft preservation

`send_message`, worker results, handoffs, context and recruit notifications never type into the human composer. Each AgentDeck MCP tool result automatically carries up to 16 pending inbox events. `read_inbox` returns the same stable IDs until `acknowledge_inbox(message_ids=[...])` confirms receipt. Agents deduplicate by ID; acknowledgment does not change task approval or assert that work was processed. Senders must supply a unique `message_id` and reuse it on retries. Calls without that key fail without enqueueing.

The journal survives process stop/restart and is bound to the logical session UUID/profile/directory. Removing a session retains its journal evidence without redirecting it to a same-name replacement. This prevents background events from moving the caret, clearing text, stealing focus or submitting login/approval/password prompts.

Idle TUIs are not force-woken. A provider must make an AgentDeck tool call to receive its pending updates; this boundary deliberately keeps human drafts untouched. Initial tasks still start automatically through supported provider launch arguments; custom commands need `{initialPrompt}` for automatic startup. No “empty prompt” inference is made from an idle status.

## Usage semantics


- Account allowance is separate from session context. The window groups default local accounts by CLI profile; it does not sum the same quota across sessions.
- Codex and Claude provide live quota windows and reset dates when their local login permits it. Gemini uses existing Code Assist credentials and reports expired login explicitly.
- Grok, Antigravity and custom providers remain visible with unsupported account fields shown as unavailable. No guessed subscription limits or reset schedules.
- Samples show source, observation time and stale errors. Refreshing does not modify sign-in or spend credits/model tokens.

## Native interaction

- Menu-bar status summarizes managed sessions and attention requests.
- ⌃⌥⌘Space opens the next approval, blocked/review task, or waiting CLI. ⌥⌘1/2 switches Work/Sessions.
- Workspace, panel, disclosure and pane transitions use a short smooth animation. Reduce Motion disables positional animation.
- Native PTY resources remain owned by TerminalHost. Layout changes reuse the same pane identities.

## Shared browser sign-ins

The owner selected shared sign-ins for all browser panes, including agents. Existing companions migrate to the current shared persistent WebKit profile once; original separate-profile data is retained. A profile menu in each browser and the inspector can restore Separate account. Closing an agent cannot clear shared cookies.

AgentDeck stores no account passwords. WebKit owns local cookies and website storage under the macOS user account. A service may still expire or revoke sign-in. Shared sign-ins deliberately permit agents to use the same accounts, while their browser tool calls remain restricted to their own tabs.

## Verification

- Regression cases cover approval bypass, ownership scope, recipient acknowledgment, duplicate/stale handoffs, restart recovery, dependency cycles and legacy state migration.
- Usage parsing tests cover quota buckets, missing/invalid data, fractional reset dates and stale samples after failures.
- A hostless rendering test uses temporary state and synthetic provider samples; it never launches paid agents or reads credentials.
- Read-only local smoke check on 2026-10-28: Codex account API returned one weekly window; Claude returned five-hour and weekly windows. Gemini's default credential was expired and correctly reported unavailable.
- Release 0.1.13 validation: all 74 XCTest tests passed, strict formatting/lint and the Release build passed. The native rendering artifact was visually inspected; real Google authentication and the menu-bar/global shortcut still need acceptance after relaunch.
- Browser tests verify shared cookies across agent panes, retention after agent removal, restoration using the same persistent profile, and preservation of an explicit Separate account choice after migration.

See [[Architecture]], [[Operations]], and [[Decisions]] for boundaries and release details.

## Explicit worker continuation (0.1.36)

Repeated `delegate_task(task_id)` is an identity lookup, not a new turn. Supplying
continuation instructions to an existing worker now returns an error explaining
`resume_worker`; the instructions are never silently discarded. Inbox delivery
still never wakes a terminal.

The parent can call `resume_worker(worker_id, request_id, instructions)` using a
fresh UUID for a new explicit request. Retry the identical request with the same
UUID. Read `worker_resume_status(request_id)` for the receipt. The worker's sidebar,
mini-window menu and inspector also expose **Resume Worker…** with a dedicated
instruction editor. Neither path reads or writes the terminal composer.

| Receipt | Meaning |
| --- | --- |
| `checking` | Request persisted; transport checks pending, no execution claim |
| `submitting` | Native queue acceptance has not been confirmed |
| `queued` | Provider accepted an identified submission; not a verified turn start |
| `started` | Native start receipt or matching live client-message event identifies the actual turn |
| `ended` | That provider turn ended; this does not complete or approve its task |
| `failed` | Known failure; detail states whether an exact queued entry was removed |
| `cancelled` | Pre-submission cancellation, or verified idle after exact cancellation/reconciliation |
| `uncertain` | Submission/observation was interrupted; never replay with a new ID |

Supported capability: local Codex shared app-server with the experimental native
queue protocol (verified with CLI 0.169.0), an exact saved conversation ID, matching
working directory and an already-loaded idle provider thread. Active/unloaded
threads, missing saved IDs, unavailable servers and other providers fail explicitly.
AgentDeck never guesses the last conversation, creates a second provider writer,
or falls back to paste/Enter. A standalone TUI without this shared transport is
unsupported. Preserve it and its draft; a user may arrange a provider-native shared
session separately. Resume itself does not migrate or terminate old sessions.

The short-lived proxy is closed with a termination callback and bounded waits:
300 ms after graceful termination, then at most 300 ms after killing a stuck proxy.
Cleanup is idempotent and does not use `Process.waitUntilExit()`; its run-loop wait
could otherwise prevent a disconnected provider's failure/uncertainty receipt
from reaching the UI. This cleanup never terminates the shared provider server.

The native queue can be consumed by the attached TUI before AgentDeck's explicit
queue-start request. In that case AgentDeck verifies the live user-message client
ID and turn ID; it never starts a second turn. Native queue input is distinct from
the human composer. The preflight rejects active workers; a concurrent native turn
cannot be steered by this queue operation.

`cancel_worker_resume(request_id)` cancels the exact known turn. For an uncertain
receipt, it explicitly reconciles only this request's queue ID and checks that the
provider is idle. It leaves unrelated/unknown active turns alone. If verification
fails, the reservation remains uncertain. **Cancel / reconcile** exposes this in
the UI. Explicit Stop persists across restart; **Enable Resume** is a user action
and does not itself start work. Resolve pending continuation before ownership
transfer, handoff, promotion, removal or terminal restart.

Use `report_subagent_progress(summary)` for an unfinished checkpoint. It leaves the
task in progress and publishes a parent inbox notification. Use
`report_subagent_result` only for a final deliverable or explicit blocker. Submitted
review/approval tasks must be explicitly reopened before continuation. Approval
always stays with the user; there are no automatic continuation loops.
