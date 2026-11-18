# Operations

Generate the project from `project.yml` (the Xcode project and `build/` are ignored), verify with `make check`, release by bumping the patch version and running `make install`, then relaunch by hand. `make dmg` packages the same version for other Macs.

## 1. Commands

| Command | Check |
| --- | --- |
| `make format` | format sources, tests and icon script with Xcode's `swift-format` |
| `make lint` | strict formatting and style diagnostics |
| `make test` | hostless XCTest bundle, Debug build, temporary state and repositories |
| `make build` | Release application build |
| `make check` | lint, tests, Release build |
| `make install` | install to Applications and trash duplicate build/backup apps |
| `make run` | install, clean up duplicates, open the Applications copy |
| `make cleanup-installs` | remove duplicate AgentDeck apps under `build/` after installation |
| `make dmg` | notarized disk image in `build/dist`; `UNSIGNED=1` builds a local test image |

- Swift 5 language mode with complete concurrency checking; macOS 14 compatibility; SwiftTerm pinned at 1.99.1.
- Lint and format need an Xcode toolchain with `swift-format`. The Makefile uses Bash pipefail so a compiler failure cannot hide behind the output tail.
- Pre-commit gate: `git config core.hooksPath .githooks` runs lint, format, tests and build. It is not installed automatically.

Native rendering fixtures need an unlocked graphical session. A locked screen can
stop the view-based display link even while the test window is attached and PTY
echo succeeds. `TerminalLatencyTests` reports the failed stage, render counters
and screen-lock state, then stops at the first timeout. Unlock the screen and
rerun with the normal renderer; an alternate display-link diagnostic is not a
substitute for the native gate. Background output fixtures stay alive until
teardown, with a 120-second safety alarm for an abandoned runner.

## 2. Releasing locally

- Increment the patch version in `project.yml`, build, replace `/Applications/AgentDeck.app`, then quit and reopen AgentDeck. A `make build` alone leaves a running installed app unchanged.
- Verify the installed bundle version and the visible feature after relaunch. User state and browser profiles live outside the bundle.
- Keep only the latest verified `/Applications/AgentDeck.app`; keep no `.app` backups. The cleanup script checks bundle identity, refuses to discard a build newer than the installed one, trashes duplicates, unregisters them and leaves other apps alone. Builds and tests recreate bundles, so run cleanup again after validation. `AGENTS.md` records the same rule.
- Local acceptance on 0.1.7 confirmed tab strips in CLI mini-windows, ⌘T and **+** adding a Codex instance to the same pane, and closing a tab without removing its siblings.
- Local 0.1.14 verification on 2026-10-29 passed the 80-test suite, eight focused resize/layout tests after the scroll-preservation adjustment, strict formatting/lint and the Release build. Installed bundle versions both read `0.1.14` and deep strict code-sign verification passed. Native fixture previews show dots in both layouts. The active AgentDeck host was left running; relaunch activates the installed fixes.
- Local 0.1.15 verification on 2026-10-29 passed 89 tests, strict formatting/lint, Release build and installed deep strict code-sign verification; both bundle versions read `0.1.15`. Current Claude, both Codex panes and Grok each have a distinct validated resume checkpoint prepared from live process metadata. The current host remains running; actual provider resumption is exercised on the next user relaunch. Evidence: `/tmp/agentdeck-resume-verified-tests.log` and `/tmp/agentdeck-resume-install.log`.
- Local 0.1.16 verification on 2026-10-30 passed the 102-test full suite, then all eight focused worker tests after the final close/exit and MCP-routing checks. Strict lint, Release build and installed deep strict code-sign verification passed; both bundle versions read `0.1.16`. Duplicate Debug/Release apps were trashed. The active host remains running; relaunch loads the new UI and MCP tools. Live provider delegation and real Keychain access were not exercised. Evidence: `/tmp/agentdeck-subagent-final-tests.log`, `/tmp/agentdeck-subagent-focused-tests.log`, `/tmp/agentdeck-subagent-install.log`.

- Local 0.1.18 verification on 2026-11-06 reproduced the stale worker role in a failing parent-close regression, then passed all 11 focused worker/promotion tests and the full 109-test suite. Format, strict lint, Release build, installed version keys and deep strict code-sign verification passed. Debug/Release duplicate apps were trashed; `/Applications/AgentDeck.app` is 0.1.18. The current host and live user state were left untouched. Relaunch repairs saved orphan roles before CLI startup; real provider acceptance after that relaunch remains unverified. Logs: `/tmp/agentdeck-promotion-{focused,full-tests,format,lint,install}.log`.

- Local 0.1.39 verification on 2026-11-18 covers the focus-ring inset, the resume-proxy kill path and disk-image packaging. The suite passes 221 tests with 4 opt-in skips; format, strict lint and the universal Release build pass. `FocusRingClearanceTests` fails on the 0.1.38 layout (inset set to 0: 24 ring pixels over the focused terminal) and passes with the inset. The Release app is ad-hoc signed with the hardened runtime and an empty entitlement set. The Release test bundle also passes inside a hardened-runtime copy of Xcode's `xctest` runner: PTY shells, CLI launch stubs, WebKit panes and sign-in popups, and the loopback MCP listener all ran under the hardened runtime. That runner carries one loader exemption, `disable-library-validation`, to load the ad-hoc test bundle. The 20-terminal scroll fixture measures the same as 0.1.38 in interleaved runs (median p95 input latency 40.3 against 40.9 ms). `make dmg UNSIGNED=1` produced a mountable universal 0.1.39 image. Not exercised: the hardened Release app itself, because no isolated-state launch exists and a second instance would share the MCP port and browser profiles; the Intel slice, because this Mac has no Rosetta; real provider CLIs; and real signing and notarization until Developer ID credentials exist (the signed path ran only against stubbed Apple tools). Evidence: `/Users/mkontsek/gitrepos/agentdeck/output/task108/`.

## 3. Releasing a disk image

`make dmg` runs `scripts/make-dmg.sh` and writes `build/dist/AgentDeck-<version>.dmg`.
End users install from that image and need neither Xcode nor xcodegen.

Prerequisites, once per Mac:

- A **Developer ID Application** certificate with its private key in the login keychain (developer.apple.com → Certificates). `security find-identity -v -p codesigning` lists it. An Apple Development certificate cannot be notarized.
- A notarytool keychain profile: `xcrun notarytool store-credentials agentdeck-notary --apple-id <Apple ID> --team-id <team>`. It asks for an app-specific password and stores it in the keychain. Never put the password in a file, a command line or the repository.
- `DEVELOPER_ID` selects an identity by name or SHA-1 when the keychain holds several; `NOTARY_PROFILE` names another profile.

Procedure:

1. Bump the patch version in `project.yml`, run `make check`, pass the merge gate and merge to `main`.
2. `make install`, so the installed app is the version being packaged.
3. `make dmg`. It checks the identity and the notary profile before building, then stops at the first failure.
4. Publish that one file: `gh release create v<version> build/dist/AgentDeck-<version>.dmg --repo mkontsek/agentdeck --target <full commit> --title "AgentDeck <version>" --latest`, with its SHA-256 in the notes.
5. Download the published asset and run `spctl -a -t open --context context:primary-signature -vv` on it.

What the script does:

- Builds the universal Release app and refuses a product that is not `arm64` plus `x86_64`.
- Copies it to a temporary staging folder, signs nested code and then the app with `--options runtime --timestamp` and no entitlements.
- Notarizes and staples the app, builds a compressed (UDZO) image named `AgentDeck` holding the app and an `/Applications` link, signs the image, notarizes and staples it. Two submissions, so the app copied out of the image carries its own ticket.
- Mounts the image without showing it in Finder and checks the version, both architectures, `codesign --verify --deep --strict`, the hardened-runtime flag, an empty entitlement set, `spctl -a -vv` on the app, `spctl -a -t open --context context:primary-signature -vv` on the image and `stapler validate` on both.
- Removes the staging folder, then runs `make cleanup-installs`. Cleanup refuses while the packaged version is newer than the installed one; step 2 avoids that.

`make dmg UNSIGNED=1` skips signing and notarization and writes `AgentDeck-<version>-unsigned.dmg` with the ad-hoc build signature. Use it to test the image layout. Gatekeeper rejects it on another Mac; never publish it. The script itself uploads only to Apple's notary service.

Release builds use the hardened runtime and carry no entitlements; see [[Decisions]]. Debug builds and tests do not use the hardened runtime, so a hardened-runtime regression shows only in a Release app. Check PTY start, a CLI launch, a browser pane with a sign-in popup and the MCP port after the first relaunch of a new release.

## 4. Regression coverage

Local 0.1.26 verification on 2026-11-08 covers native focus retention (including visible WebKit automation, selection/IME and pointer/Tab navigation), capped reversible terminal fonts, bottom-right-only resizing, cached obstacle-aware rounded arrows and an independent Settings color. The universal Release suite passes157 tests with3 opt-in skips and0 failures. Changing provider title/status presentation is coalesced without buffering PTY output; lifecycle tests reject stale metadata. Strict lint, Release signature and native light/dark route checks pass. The source preserves task60 explicit paste, task79 inbox, task76 limits, task77 tabs, task78 OAuth, task80 layouts and task81 drawing behavior. Installation/activation evidence and the bounded review ledger are in `/Users/mkontsek/gitrepos/output/task79-focus/report.md`. An install does not restart existing sessions.

Local 0.1.25 verification on 2026-11-08 adds default owned-browser splits, fit-to-width browser zoom, native title-bar double-click full-canvas maximize/restore, synthetic Demo mode, and antialiased filled arrowheads. Two universal Release suite runs pass 146 tests with three opt-in skips; eight final focused tests pass after restoring malformed-zoom bounds. Native WebKit, host/focus identity, Demo light/dark OCR masking and filled/antialiased arrow pixel checks pass. Format, strict lint and final universal Release build pass; bounded review PASS 3/4. Both installed version keys, signature and exact executable/bundle hashes match the verified artifact. Only `/Applications/AgentDeck.app` remains launchable. Host PID 84551 retains its original 00:04:45 start time; relaunch is left to the user. Evidence: `/Users/mkontsek/gitrepos/output/task80-split/result.md`.

Local 0.1.24 verification on 2026-11-07 adds startup fitting, automatic/manual text sizing, browser tabs inside their owning agent, right-angle connections and background redraw deferral during scrolling/typing. The exact final universal Release suite passes 141 tests with three opt-in skips. Format, strict lint, native light/dark rendering, ownership/migration, focus/PTY identity and installed signature/version checks pass. The installed and independently rebuilt binaries match every pre-signature code byte; only signature data differs. The 20-PTY scrolling fixture improves p95 loop time from 45.54 to 32.18 ms and input echo from 28.75 to 18.38 ms; typing median render-observed time improves while its p95 is essentially unchanged. `/Applications/AgentDeck.app` is 0.1.24; duplicates are trashed. Host PID 28916 retains its original 23:12:34 start time; user relaunch activates the changes. Evidence and limitations: `/Users/mkontsek/gitrepos/output/task80-fit/result.md`.

Local 0.1.23 verification on 2026-11-07 integrates connected worker/browser windows, the coordination inbox and unchanged-metadata suppression. The exact final suite passes 135 tests with three opt-in skips; both real disposable Codex draft/MCP cases pass separately. Native migration, multi-owner WebKit isolation, movement/resize/maximize, restoration and light/dark connection checks pass. Format, strict lint, universal Release build, installed version keys, exact executable hash and deep strict signature pass. Installed `/Applications/AgentDeck.app` is 0.1.23; the existing host PID 74651 remains running with its original start time. Relaunch at a user-chosen time activates the new code. Evidence: `/Users/mkontsek/gitrepos/output/task80/result.md`; full VoiceOver and live provider restoration after relaunch remain manual acceptance items.

- Popup regression (`Tests/Browser`): actual WebKit UI callbacks over two loopback origins; child-to-opener messages, DOM close, preserved parent, supplied configuration, named blank-window POST, native close, nested cleanup/restart, shared/isolated fixture cookies, explicit noopener and rejected native/file/script schemes. Only throwaway profiles are removed. No credentials or real provider login are used.

- HTTP: malformed and fragmented requests, UTF-8 framing, origin/host checks, live loopback requests, listener shutdown, JSON-RPC and board actions, invalid ports.
- Store: stopped-session injection, shell-template quoting including combining marks, large stderr, worktree collisions and dirty deletion, failed recruit isolation, state round trips and corruption, status heuristics, PTY restart/exit and stale delayed Enter.
- Browser: WebKit stop/render/restart on a local HTML page, an attachment saved into the configured download folder, and a companion driven end to end on a `data:` page (navigate, read, click by text, type and submit, eval, screenshot from a parked view, removal with the owner) in a throwaway window.
- Tabs: legacy pane migration, per-pane selection persistence, shared geometry and canvas packing, neighbor selection on close, maximized/sidebar navigation, referenced-worktree protection, hidden output and focus with disposable shell PTYs.
- Profiles: expanded launch arguments via shell-function stubs including bypass flags and quoted MCP paths, legacy command migration, custom-command retention, persisted opt-outs.
- Browser profiles: shared cookies, separate-account isolation, retention when a shared pane is removed, restoration from saved state, switching modes without starting a stopped pane, shared companion sign-ins, restoration after agent removal, one-time migration and explicit separate-account selection.
- Startup and skills: default pane composition and idempotence, persistence migration, corrupt-state startup, directory resolution, symlink cycles, deduplication, manifests escaping configured roots, oversized or unreadable files, enabled/disabled MCP access, catalog exports, stale reload cancellation, browser log redaction.
- Tests never launch paid agents or load saved AgentDeck state; browser tests create a fresh WebKit profile and delete it afterwards. The test target lists production sources explicitly in `project.yml`: add new `Sources` files there.
- Coordination tests cover gated completion, owner/recipient permissions, durable handoffs, stale context and dependency cycles. Usage tests inject synthetic samples; normal test runs never read CLI credentials or call account APIs.
- The rendering test writes `/tmp/agentdeck-coordination-preview.png` using isolated state and fixture usage. Native layout regression checks preserve the same terminal container across animated grid/canvas/maximize and Work/Sessions transitions.
- PTY tests wait for the shell to print a ready marker instead of sleeping a fixed time, because `zsh -l -i` startup takes seconds under load and flushes type-ahead.
- Window chrome regression tests cover all eight directions in the geometry helper, boundary/minimum sizes, and the native bottom-right-only resize grip. Other borders and header controls pass through normally. Hosted drag events verify grid-to-canvas resizing preserves the terminal container, usage shrinks immediately from a viewport-clamped size, and geometry survives saving. Pixel checks verify dots in dark/light Grid and Canvas. Preview images are written to `/tmp/agentdeck-resize-preview.png` and `/tmp/agentdeck-dots-<appearance>-<layout>.png`.
- Focus ring: `FocusRingClearanceTests` checks that the content inset clears the ring on straight edges and inside its corners, that first-column glyph ink is never under a border at 5 to 40 pt, and, in a hosted pane in both themes, that the terminal frame, column count and row count stay the same across focus changes, that no border-coloured pixel lies over the terminal and that the gutter has the terminal's background colour. A second hosted case covers a terminal beside and above its owned browser. Previews: `agentdeck-focus-ring-*.png` under the user temporary directory.
- Packaging: `DiskImageScriptTests` runs `scripts/make-dmg.sh` with `security`, `xcrun` and `make` replaced by stubs. It covers identity detection and explicit choice, rejection of non-Developer ID certificates, the missing notary profile, the `UNSIGNED` flag, failure before any build, notarization status handling and the innermost-first order of nested code. It builds, signs, uploads and mounts nothing. `WorkerResumeTransportTests` closes a fixture proxy that ignores SIGTERM and expects the kill within the bounded wait.
- Resume tests use fake provider files, open-file metadata and harmless shell stubs: separate same-directory tab identities survive save/reload and bootstrap, explicit opt-outs remain, missing/stale/ambiguous identities are rejected, initial tasks are not replayed, and client-side browser URLs persist. No real provider conversation is started by these tests.

## 5. Settings worth knowing

- Settings → General can disable automatic defaults on an empty launch.
- Settings → Skills controls folders and enabled skills; use Reload after editing. The catalog is `~/Library/Application Support/AgentDeck/skills/catalog.md`.
- Settings → Skills accepts a folder path and search query, with individual and filtered bulk enable/disable controls. Changes affect future catalog/MCP reads immediately; existing conversation context remains.
- Settings → Orchestration controls automatic workers, their concurrency limit (1–20, default 20) and independent worker windows. Version 0.1.19 migrates the previous default of 3 to 20 once; other saved limits remain unchanged. A saved choice of 3 can be selected again after migration. Retained workers are capped at 40 per parent. Existing app processes require a restart to load changed limits; finish active work before restarting. New/root CLI conversations receive the delegation policy through briefing and MCP initialization; reconnect/restart older clients to refresh their tool catalog.
- Ordinary CLI and browser tabs stack one per row (three visible, one in compact panes), then scroll vertically. Every worker has a separate mini-window; browser tabs live inside their owner’s mini-window. Restart preserves saved sizes and canvas positions across viewport changes; saved grids reopen as fixed canvas geometry. Only an initially empty workspace fits its first windows automatically; use Fill Canvas to rearrange existing windows. Text scales with window size unless manually overridden. Drag its title/grip, resize from its bottom-right grip, or use Window actions for movement, size presets and maximize. Relationship buttons navigate parent → worker → browser; see [[Connected-Mini-Windows]]. The board retains results when the parent is stopped or closed.
- Closing a parent now promotes its surviving workers to ordinary main conversations. Old saved orphan workers are repaired automatically on launch. To detach a worker while its parent remains open, choose **Promote to Main Conversation** in the session sidebar menu or inspector. Tasks, approval state and provider history remain intact; the obsolete initial worker prompt is removed. Restart a running promoted CLI to refresh its persistent instructions and cached MCP tools. Automatic subagents must still be enabled; the Orchestrator toggle is not required for `delegate_task`.
- `SubagentSessionTests` and `SubagentPromotionTests` cover fresh/idempotent delegation, focus/selection persistence, limits, completion gates, ownership/handoff/dependency guards, early exits, parent-close promotion and legacy orphan recovery for Claude/Codex. Hosted connected-window tests exercise independent movement, resize, maximize, grid/canvas transitions, accessibility relationships and host identity with disposable `/bin/cat` PTYs and local WebKit pages. Task/profile snapshots are written under the macOS user temporary directory (`getconf DARWIN_USER_TEMP_DIR`) as `agentdeck-task-dialog.png`, `agentdeck-profiles.png` and connected-window snapshots under `/tmp/agentdeck-connected-*.png`.
- Usage regression fixtures cover reopen throttling, cancellation retry, manual refresh, credential expiry/invalidation, and restoring the legacy interaction switch after a throwing read. Tests do not read real credentials or exercise a live provider turn.
- Missing agent commands show setup links; authentication stays interactive.
- If saved state cannot decode, back up and repair `~/Library/Application Support/AgentDeck/state.json`, then restart. Saving stays disabled until restart; alerts report write errors.

## 6. Manual acceptance still needed

- After upgrading, restart CLI processes to activate migrated launch instructions. Check identity/board/skills before and after a conversation reset and exact resume for each provider. Gemini/Antigravity use the default global `~/.gemini/GEMINI.md` bootstrap; custom context discovery must load that file. Remove only the marked AgentDeck section to uninstall the bootstrap. No live model acceptance is implied by shell argument and native UI regression tests.

- Sign in to each website; embedded WebKit OAuth restrictions vary by provider. Version 0.1.22 preserves OAuth popup configuration/opener semantics. Install while the host runs, then relaunch only when active sessions may be interrupted. Retest the exact requested Claude artifact after relaunch; existing browser instances keep the old implementation until then. Do not infer provider success from the local popup fixture.
- Exercise installed CLI versions, credentials, MCP setup and a real model turn.
- Check canvas dragging, resizing, shortcuts, theme and multi-window behavior by hand.
- Test the oldest supported macOS and Intel hardware; local verification uses the Apple Silicon SDK and runtime.
- Check menu-bar access and ⌃⌥⌘Space in the installed app; a conflicting global shortcut is logged without disabling the menu-bar action.
- After the first relaunch of a hardened-runtime release (0.1.39 on), check in the installed app: a terminal pane starts its shell and CLI, a browser pane loads and completes a sign-in popup, an agent reaches the MCP port, and `osascript -e 'tell application "Finder" to get name of startup disk'` answers in a terminal pane.
- When AgentDeck hosts the agent performing the update, install the verified bundle without quitting the running host. Relaunch after active sessions can be interrupted; installing alone does not change its running code.

## Automatic message submission

AgentDeck 0.1.20 introduced separate paste and submit operations. Version 0.1.23 retains this path for explicit user input and routes background worker messages through the coordination inbox instead. Replacing the bundle does not patch an already running host. `MessageSubmissionTests` checks exact negotiated paste boundaries and a distinct submit key with a long Unicode message. Existing lifecycle tests reject delayed submission into a replacement process and agent injection into a plain shell.

An optional live Codex check requires the installed CLI and existing sign-in, starts a disposable session, sends one harmless arithmetic prompt without tools, and checks its answer. Run with `TEST_RUNNER_AGENTDECK_LIVE_CODEX_SUBMIT=1` and `-only-testing:AgentDeckTests/MessageSubmissionTests/testLiveCodexAcceptsAutomaticSubmission`; ordinary tests skip it and never invoke a real model. The check does not confirm login, trust or other interactive setup dialogs.

## Task79 coordination inbox

- `coordination-inbox.json` beside `state.json` stores only intentionally published messages, never composer text. It is independent of the older host's state writer. Keep it with session backups. Atomic acceptance precedes success responses; corrupt files are preserved and produce an error.
- A journal accepts at most 4096 events / 8 MiB (with receipt-growth reserve). Acknowledged records retain IDs for deduplication. Full journals reject new acceptance visibly rather than deleting pending events. Archival is an explicit maintenance operation after reviewing pending receipts; do not remove it while a host is running or expect deduplication across a manually replaced journal.
- Safe automatic startup: built-in Claude/Codex/Grok prompt argv and Gemini/Antigravity `--prompt-interactive`. Custom templates can position `{initialPrompt}` explicitly. Otherwise startup instructions wait in the inbox and require a provider tool call.
- `Tests/Subagents/DraftPreservationTests.swift` uses an isolated SwiftTerm PTY with multiline Unicode, mid-text input, native selection/IME, statuses, user Enter and stop/restart. Inbox tests cover atomic failure, corruption, idempotency, receipts, batch order, HTTP attachment and replacement identity. `InitialPromptTests` verifies literal argv and no replay on resume.
- Live provider check is opt-in: build tests, then run `AGENTDECK_LIVE_DRAFT=1 xcrun xctest -XCTest LiveDraftProviderTests build/Build/Products/Debug/AgentDeckTests.xctest`. It launches only a disposable Codex, requests a tool-free arithmetic answer via argv, adds a synthetic draft, and verifies worker events leave its screen/caret unchanged. A second fixture holds an actual MCP response while editing a draft, then verifies inbox acknowledgment and logical caret preservation. It never submits the synthetic draft or sends input to existing sessions. Xcode test launching does not automatically forward this environment flag.

## Safe worker resume verification

Version 0.1.36 adds explicit native continuation for verified shared-server Codex
threads. Other transports fail safely; see [[Coordination-and-Usage]]. Existing
hosts keep their loaded code until the user relaunches. Installing does not restart
them or migrate active terminals. Preserve `worker-resumes.json` along with state
and resume checkpoints. Never delete its IDs to force a retry after uncertainty.

`WorkerResumeTests` and `WorkerResumeTransportTests` cover the original silent-reuse
regression, owner/state guards, native queue/start receipts, active races, literal
Unicode/shell-looking text, failure, cancellation, persistence and stale callbacks.
The opt-in live test launches its own local server and synthetic Codex thread,
attaches its own TUI, leaves a Unicode draft with a mid-text caret and native IME,
and verifies an actual second response through `resumeWorker`. It never targets
existing user sessions or reads their transcripts:

```sh
make test
AGENTDECK_LIVE_RESUME=1 xcrun xctest -XCTest LiveWorkerResumeTests \
  build/Build/Products/Debug/AgentDeckTests.xctest
```

The test uses the installed CLI's existing sign-in. A missing capability, setup
screen or transport fails visibly; it never confirms dialogs or submits draft text.
The provider's synthetic thread history is retained; no user resume data is removed.
