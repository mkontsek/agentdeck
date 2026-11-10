# Decisions

## 2026-11-10: Shared status indicators and sidebar keyboard focus

The user observed yellow attention balls alongside green session circles and requested Up/Down navigation in the Sessions sidebar. Reuse the existing ball's task-aware presentation calculation for dots and tab icons, with one shared palette. Do not change runtime heuristics or the statuses exposed to MCP; retain those diagnostic values under an explicit Runtime label. Owned browser tabs resolve to the same agent presentation.

Native reproduction showed the list's first arrow selection calling `selectTab`, which immediately made the terminal first responder. Split sidebar selection/reveal from explicit native activation. The list keeps focus through native Up/Down selection; Return or a direct pane click activates the selected native view. Keep all key handling scoped to the sidebar so terminal/editor/browser arrow input and marked text are unaffected.

## 2026-11-10: Fixed sphere tangents and continuous map drags

The user requested arrows touching spheres and staying stationary throughout slower expansion/collapse. Reserve each full window footprint for routing and choose one shared docking side from parent/worker layout geometry, independent of focus and status. Place the sphere internally tangent to the edge midpoint and scale the retained window about that same point. Route all relationships on a worker through its dock; preserve the existing rounded orthogonal router and clearance/fallback limits. Attention pulses only the glow, preserving exact contact. Shape transitions use a separate 420 ms smooth animation, 50% longer than the earlier 280 ms policy; other workspace animation is unchanged.

This avoids freezing an endpoint detached from the visible surface or rerouting bends as a shape grows. Consequences: routes may traverse empty space around a collapsed footprint; multiple edges may share a short segment. A covered dock omits the line and retains relationship navigation. Genuine movement, resizing, layout or relationship changes recompute geometry. No geometry is persisted by this presentation change.

The user also reported map dragging releasing immediately. The map had used its clipped viewport rectangle as a gesture-size identity; boundary clipping and fractional coordinate rounding could cancel the drag's own subsequent updates. Preserve the original unclipped viewport alongside the drawn rectangle, with a sub-half-point size tolerance for native rounding. Keep source generation, canvas bounds and map-size guards, so actual replacement or resizing still cancels stale gestures. This changes no keyboard responder, draft or global workspace publication behavior.

## 2026-11-10: Click to expand glass balls and drag the canvas map

The user replaced hover expansion with explicit click activation and asked for interactive map panning plus smooth transitions. Remove hover tracking entirely. Keep expansion tied to explicit session selection, and provide a Collapse to glass ball action. Use the shared 280 ms smooth, non-bouncing motion policy for workspace transitions; Reduce Motion settles directly. Keep native terminal geometry fixed while scaling/fading layers, and defer hiding until the current animation completes. A revision guard makes interruptions/reversals safe without a timer guessing when an animation ended.

The map is now a navigation control. Preserve the pointer's grab offset inside the viewport and center on clicks outside it. Bind navigation to the observer and snapshot attachment; stale map gestures cannot move a replacement canvas. Native clip-view constraints clamp the target and direct dragging follows the pointer without a trailing animation. Keep focus/caret/selection untouched and avoid global AppStore publications during panning. This supersedes the November9 hover/passive-map decisions below. The animation audit keeps explicit workspace state changes on one policy; ongoing PTY output and direct manipulation are not implicitly animated.

## 2026-11-09: Collapse subagents into status glass balls

The user requested a performance-saving glass-ball mode with hover expansion. Persist only the opt-in toggle; preserve the normal pane geometry and native resource identities. Hover is passive and transient. Keep focused panes expanded so pointer exit cannot hide a typing target; explicit sidebar, keyboard or ball selection opens the pane using the existing focus path.

Use working/attention/finished/idle states with symbols and accessible labels. Attention takes precedence over completion and includes pending task review/approval; idle alone is not proof of success. Only attention pulses, with Reduce Motion respected. Feed displayed compact bounds to connector routing and the canvas overview. Hide retained WebKit views and separately gate terminal paint invalidations while continuing PTY parsing. Do not claim to suspend browser scripts or provider execution. This is a rendering optimization, not input coordination or a new session lifecycle.

## 2026-11-09: Resize the terminal/browser split without replacing native hosts

The user requested a movable vertical separator inside each mini-window. Keep the existing stable AnyLayout/session identity and add a narrow native divider, also supporting the stacked compact layout. Mouse positions are measured in window coordinates so moving the divider does not distort subsequent drag deltas. Keep previews local and persist the per-owner ratio only on release, avoiding global terminal-pane invalidations on every mouse move.

Default older sessions to equal shares, bound stored ratios and adapt minimum sizes to small containers without overwriting the saved preference. Cancel obsolete gestures when their owner, visible pair, axis, size or native attachment changes. Do not request focus or touch provider input; task79's separate coordination inbox and task60's explicit paste/Enter path remain unchanged. Double-click resets equal shares and accessibility adjustment uses the same setter.

## 2026-11-09: Show the canvas viewport in the Sessions sidebar

The user requested a small mini-window diagram showing the viewport relative to the whole canvas. Keep it anchored beneath the scrollable session list, with window rectangles and a distinct dashed viewport outline. Use native scroll geometry rather than inferring the viewport from focus or stored window positions. The map remains a passive overview; existing scrolling and relationship navigation retain their input behavior.

Publish transient geometry through a separate observable owner instead of AppStore's global publisher, so panning does not invalidate every terminal pane. Coalesce updates within one main-queue turn, deduplicate equal snapshots and bind callbacks to the attached native observer. Show only the expanded pane in maximized mode, matching the currently displayed canvas. Persisted layout and provider/session identity remain unchanged.

## 2026-11-09: Preserve mini-window geometry across restart

The user wants saved sizes and positions retained even when the next canvas has different dimensions. This supersedes the November 7 decision to fit every window at every startup. Fit only an initially empty workspace's first windows; restored panes keep their stored geometry and off-screen panes remain reachable by scrolling. Explicit Fill Canvas, Tidy and Grid still rearrange the workspace when requested.

Snapshot a measured grid's normal frames into the existing persisted canvas fields and reopen it as a fixed canvas. Do this on the saved value copy so neither a save nor a temporary maximize changes the live grid. Reusing these fields avoids a second layout schema or a viewport-dependent reconstruction. Older grid saves did not record the displayed frames; retain the canvas geometry they contain. Provider sessions, native hosts, draft handling and coordination delivery are unchanged.

## 2026-11-08: Preserve native focus before responder transfer; route visible connectors

Native tests reproduced WebKit asking NSWindow for focus, causing AppKit to resign a terminal before WKWebView rejected the request. Restoring focus afterward would already have disturbed typing/IME. A narrow, one-time public-method interception checks owned browser targets before resignation; ordinary AppKit responders pass through. Explicit user pane selection and actual pointer/Tab dispatch grant focus synchronously. Passive mounts may only fill an unclaimed responder chain. This preserves SwiftUI's native window lifecycle without replacing its window class or reading drafts.

Automatic terminal fonts use geometry with the configured size as a ceiling; manual overrides remain fixed. The resize hotspot is bottom-right only. Connector geometry is cached and routed around window borders, with a small corner radius and independent persisted color. Fully covered endpoints retain their labeled relationship navigation.

A changing-title native output fixture exposed thousands of global publications despite earlier unchanged-title suppression. Presentation metadata now coalesces at 100 ms across terminals, guarded by terminal identity/generation; raw output, input, task60 explicit paste/Enter and task79 inbox delivery are unchanged. Installation does not restart active sessions.


## 2026-11-08: Browser splits, width fitting and screenshot mode

The user requested terminal/browser split presentation by default, confirmed fitting page width with vertical scrolling, and requested double-click expansion over the entire canvas with exact geometry restoration. Keep browser ownership, session keys and native hosts independent from presentation. Existing saved owners default to split mode; opting out persists per owner. Browser width fitting replaces proportional browser zoom, while terminal scaling and manual text/zoom overrides remain.

Demo mode uses opaque synthetic content rather than blur so screenshots cannot reveal text through weak blur. Mask all main-window identifiers and private panels while retaining live resource owners. This is temporary UI state, not a state/profile rewrite. Connections retain right angles, explicitly antialias native strokes and fill triangular arrowheads.

## 2026-11-07: Fit startup windows and keep browsers with their owner

The owner revised task80: browser tabs belong inside each agent/subagent mini-window. This supersedes the earlier separate-browser-window choice. Independent worker windows and parent relationships remain. Persist a separate per-owner browser selection so returning to a terminal does not change the automation target.

Fit every window once at startup, then honor manual layout changes during the session. Scale text from displayed size; an explicit font override stays fixed. Use right-angle connections as requested. Native profiling found substantial CoreGraphics terminal draw cost under output load; defer background/off-screen display invalidations during canvas scrolling while keeping all parsing/input and the keyboard responder live. This reuses native layers instead of hiding views, copying terminal drafts, dropping PTY bytes, or changing the renderer.

## 2026-11-07: Connected independent worker and browser windows

- Supersedes the October 30 half-pane worker presentation. The user requested independently movable/resizable worker windows and separate owned-browser windows with visible relationships.
- Reuse persistent pane geometry and existing native resource owners; never model a new window as a new provider session. Repair old shared pane IDs idempotently before startup without replacing session/profile/checkpoint identities.
- Browser tabs group by owner, not shared sign-in profile. Shared cookies do not grant a caller control of another owner's tabs. Per-tab profile choices remain unchanged.
- Draw non-interactive directional paths and offer equivalent labeled navigation. Maximizing hides paths while retaining relationship navigation and every native host. See [[Connected-Mini-Windows]].

## 2026-11-07: Worker coordination bypasses terminal input (task79)

Task60 repaired bracketed paste/Enter timing on an empty Codex prompt. It did not protect an unfinished human prompt: native regression now reproduces a worker expanding an 84-byte Unicode multiline draft to 127 bytes. Idle status, silence and focus do not prove an empty composer.

Background paths now accept events into a separate atomic inbox and attach them automatically to MCP tool results. Stable IDs and explicit recipient receipts separate persistence, offering and acknowledgment; none means processing or completion approval. Published final tasks and handoff packages recover interrupted notification acceptance. No private terminal draft is read, stored or copied. Fresh initial tasks use provider argv; the task60 PTY path remains only for explicit human Send Input.

A provider MCP result is a verified separate channel. The installed Codex CLI also advertises `queue`, but its help supplies neither an idempotency key nor a draft/lifecycle guarantee; this change does not speculate about those semantics or attach another app-server to a human conversation. Idle TUIs keep updates pending until their next tool call. This is a documented capability limit, not a timing workaround. Installation replaces the bundle only; the running host and its agents are never restarted.

## 2026-11-06: Preserve WebKit popup handoff

- Replacing the parent with a popup URL and returning nil destroys the opener context and can change a POST into a GET. The native two-origin fixture reproduced lost parent DOM and missing callback messaging with that implementation.
- Return a new web view using WebKit's supplied configuration without modifying its website data store, process pool or content controller. Let WebKit navigate it and enforce opener/noopener semantics. This follows [Apple's WKUIDelegate contract](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:)).
- Own transient native windows under the opener instead of creating persisted browser sessions or routing authentication to the external browser. Descendant cleanup follows the parent lifecycle and effective shared/isolated profile. Show the committed origin, constrain navigation to HTTP(S)/about:blank, and cap the entire tree at eight windows.
- Google/Claude sign-in still requires provider-specific validation after relaunch. Fixture success proves the WebKit handoff defect and repair, not that a provider accepts embedded sign-in or that the requested Claude artifact is accessible.

## 2026-11-06: Promote orphaned workers to main conversations

- Closing a parent previously promoted the tab visually while retaining `delegatedTaskID`, preventing delegation and injecting obsolete worker-only instructions. Repair existing orphan records on load and clear the full role on parent removal.
- Add a user-only Promote to Main Conversation action for attached workers. Preserve task ownership, evidence, completion approval and exact provider resume checkpoints. Clear the generated initial worker prompt so a future fresh launch cannot replay the old role.
- Refresh the persisted briefing and server tool definitions immediately. Preserve running processes and show a restart notice; a typed user message cannot reliably replace launch-level instructions or refresh a provider's cached tool list. This supersedes the earlier rule that workers remain restricted after their parent closes. Attached workers retain the recursion restriction, and promotion is not an MCP tool.

## 2026-11-04: Persistent CLI briefing and browser keyboard focus

- A typed briefing pointer disappears after clearing a conversation. Use additive launch instructions for Claude, Codex and Grok, including exact resume; migrate only exact previously shipped templates.
- Gemini and Antigravity lack an equivalent additive launch flag in the installed versions. Preserve their core prompts and user rules by appending a conditional global bootstrap instruction that reads the process-specific briefing after each reset. This depends on provider context discovery and model compliance; custom global context filenames require user configuration.
- Render hidden browser automation in its own non-key/non-main panel, closed with its controller. Rejecting WebKit's focus request alone still lets AppKit clear the main window's current responder; the native regression reproduced that failure. A focused-pane guard remains for visible views. Restoring focus after an asynchronous action would interrupt a user's intervening focus change and would still drop keystrokes during the action.

## 2026-10-30: Managed task workers and quiet usage refresh

- Use separate managed CLI sessions for task workers. Provider-internal subagents have no stable cross-provider terminal identity; AgentDeck workers have their own task, PTY, MCP caller and restart checkpoint.
- Keep the parent visible and instruct it to return promptly after delegation. This preserves an available conversation without attempting to interrupt or parse a provider's active turn. The behavior still depends on the provider following its briefing.
- Start workers fresh and pass only published task context. Inherit the directory/worktree and require scoped work; do not silently create or merge worktrees. Recursion is prohibited, concurrency is bounded, and existing handoff/completion gates stay intact.
- Use a persistent parent view plus a conditional half-pane child rather than swapping the parent out of a split container. Native terminal identity and focus survive orientation changes and collapse.
- Replace CLI Profiles' selectable split-list layout with fixed-width explicit selection buttons. Use vertically labeled, scrollable task/profile fields so long labels cannot push editors outside the window.
- Cache usage samples across panel openings and Claude credentials only in memory. Modern authentication contexts alone do not suppress legacy Keychain ACL dialogs, so wrap the serialized synchronous lookup in the legacy no-interaction switch and restore it immediately. Missing access yields unavailable usage instead of requesting permissions.
- Defer the phone companion and speech input to [[Roadmap]].

Each entry records what was chosen, the alternative, and the consequence. Newest first.

## 2026-10-29: Restore each pane's own conversation

- Restart continuation is separate from first-launch directory continuation. Fresh tabs previously kept `resumeLastConversation=false` permanently; enabling it on restart alone would let same-directory agents reopen the same latest conversation.
- Capture exact Claude, Codex and Grok identities through the managed process's PID metadata/open-file names, without reading transcript bodies. Persist small atomic sidecars, refresh while running, and await a final capture before normal termination. Separate files allow the first upgrade to prepare active sessions without editing an older host's live `state.json`.
- Respect explicit restart opt-outs and custom commands. Reject missing, stale or ambiguous identities rather than attaching an arbitrary conversation. Gemini has only a single-pane best-effort fallback; unsupported providers start normally. Restart fallbacks never resend the initial task.
- Browser URL observation includes client-side chat navigation; the existing persistent browser profile supplies sign-ins. Relaunch restores conversations and pages, not live PTY processes or unsaved input.

## 2026-10-29: Mouse resizing throughout the desk

- Mini-windows and CLI usage share native AppKit edge/corner handling. Border hit testing wins over embedded native content while the interior passes clicks through; a visible bottom-right grip retains double-click reset.
- Dragging a grid pane's border switches to Canvas at the displayed frames. Keeping Grid fixed had made pane resizing unavailable in the owner's current layout. Maximized panes remain viewport-sized.
- Usage resizing uses the visible frame, not an oversized saved size, so shrinking after reducing the main window takes effect immediately. Bounds and opposite-edge anchoring prevent the panel from shifting unexpectedly.
- The dotted background now renders in Grid as well as Canvas, with the website's white 14% dots, 16-point spacing and dark background. Light appearance uses dark dots.

## 2026-10-28: Share sign-ins across agent and ordinary browser panes

- The owner explicitly chose shared sign-ins across all AgentDeck browsers, including agent-controlled panes. This supersedes the mandatory companion isolation decision from October 22 and profile lock from October 25.
- New companions use the existing shared persistent WebKit profile. A one-time migration switches old companions to it while retaining their separate-profile UUIDs and data. Later explicit Separate account choices persist.
- Closing an agent removes its companion tab but never the shared profile. The toolbar exposes the current profile; Settings can make new companions separate by default.
- No cookie copying, password database or new password prompt. WebKit persists website data locally under the macOS account; server expiry, revocation and embedded-login restrictions remain outside AgentDeck's control. Agents can use the same signed-in accounts, but browser tools still target only the caller's own tab.

## 2026-10-28: Explicit coordination and default-account usage

- Work becomes the primary workspace while Sessions preserves the native desk. Handoffs are persisted packages with independent approval, delivery and acceptance states. Ownership transfers on recipient acknowledgment, not notification delivery.
- New tasks require user completion approval; legacy tasks keep their old contract. Owner/orchestrator mutation checks and revision validation prevent accidental overwrites and stale handoff acceptance through MCP. These are app-level policies on trusted local identities, not stronger process isolation.
- Context comes from intentionally shared task fields and supplied artifacts. Automatic transcript harvesting was rejected because it contradicts private coordination.
- Account usage appears once per CLI profile in a movable mini-window. Use existing default logins and provider quota APIs; never spend model tokens or infer missing limits. Unsupported providers and expired credentials remain explicit. Custom account configurations require separate future connectors.
- Open/close and expand/collapse transitions share a 240 ms motion policy and honor Reduce Motion. Pane layout uses stable identities so animations do not replace native PTY containers. Work/Sessions keeps the terminal workspace mounted, with keyboard focus disabled while hidden.

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
