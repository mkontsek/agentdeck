# Operations

Generate the project from `project.yml` (the Xcode project and `build/` are ignored), verify with `make check`, release by bumping the patch version and running `make install`, then relaunch by hand.

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

- Swift 5 language mode with complete concurrency checking; macOS 14 compatibility; SwiftTerm pinned at 1.99.1.
- Lint and format need an Xcode toolchain with `swift-format`. The Makefile uses Bash pipefail so a compiler failure cannot hide behind the output tail.
- Pre-commit gate: `git config core.hooksPath .githooks` runs lint, format, tests and build. It is not installed automatically.

## 2. Releasing locally

- Increment the patch version in `project.yml`, build, replace `/Applications/AgentDeck.app`, then quit and reopen AgentDeck. A `make build` alone leaves a running installed app unchanged.
- Verify the installed bundle version and the visible feature after relaunch. User state and browser profiles live outside the bundle.
- Keep only the latest verified `/Applications/AgentDeck.app`; keep no `.app` backups. The cleanup script checks bundle identity, refuses to discard a build newer than the installed one, trashes duplicates, unregisters them and leaves other apps alone. Builds and tests recreate bundles, so run cleanup again after validation. `AGENTS.md` records the same rule.
- Local acceptance on 0.1.7 confirmed tab strips in CLI mini-windows, ⌘T and **+** adding a Codex instance to the same pane, and closing a tab without removing its siblings.

## 3. Regression coverage

- HTTP: malformed and fragmented requests, UTF-8 framing, origin/host checks, live loopback requests, listener shutdown, JSON-RPC and board actions, invalid ports.
- Store: stopped-session injection, shell-template quoting including combining marks, large stderr, worktree collisions and dirty deletion, failed recruit isolation, state round trips and corruption, status heuristics, PTY restart/exit and stale delayed Enter.
- Browser: WebKit stop/render/restart on a local HTML page, an attachment saved into the configured download folder, and a companion driven end to end on a `data:` page (navigate, read, click by text, type and submit, eval, screenshot from a parked view, removal with the owner) in a throwaway window.
- Tabs: legacy pane migration, per-pane selection persistence, shared geometry and canvas packing, neighbor selection on close, maximized/sidebar navigation, referenced-worktree protection, hidden output and focus with disposable shell PTYs.
- Profiles: expanded launch arguments via shell-function stubs including bypass flags and quoted MCP paths, legacy command migration, custom-command retention, persisted opt-outs.
- Browser profiles: shared cookies, separate-account isolation, retention when a shared pane is removed, restoration from saved state, switching modes without starting a stopped pane, companion profile lock.
- Startup and skills: default pane composition and idempotence, persistence migration, corrupt-state startup, directory resolution, symlink cycles, deduplication, manifests escaping configured roots, oversized or unreadable files, enabled/disabled MCP access, catalog exports, stale reload cancellation, browser log redaction.
- Tests never launch paid agents or load saved AgentDeck state; browser tests create a fresh WebKit profile and delete it afterwards. The test target lists production sources explicitly in `project.yml`: add new `Sources` files there.
- PTY tests wait for the shell to print a ready marker instead of sleeping a fixed time, because `zsh -l -i` startup takes seconds under load and flushes type-ahead.

## 4. Settings worth knowing

- Settings → General can disable automatic defaults on an empty launch.
- Settings → Skills controls folders and enabled skills; use Reload after editing. The catalog is `~/Library/Application Support/AgentDeck/skills/catalog.md`.
- Missing agent commands show setup links; authentication stays interactive.
- If saved state cannot decode, back up and repair `~/Library/Application Support/AgentDeck/state.json`, then restart. Saving stays disabled until restart; alerts report write errors.

## 5. Manual acceptance still needed

- Sign in to each website; embedded WebKit OAuth restrictions vary by provider.
- Exercise installed CLI versions, credentials, MCP setup and a real model turn.
- Check canvas dragging, resizing, shortcuts, theme and multi-window behavior by hand.
- Test the oldest supported macOS and Intel hardware; local verification uses the Apple Silicon SDK and runtime.
