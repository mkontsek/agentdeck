# Coordination and usage

The Work workspace is the app's front door. Sessions retains the terminal/browser desk. The CLI usage mini-window can be moved, resized, hidden and reopened with ⌥⌘U.

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
