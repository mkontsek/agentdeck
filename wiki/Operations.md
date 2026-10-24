# Operations

Generate the project from `project.yml`; the Xcode project and `build/` are ignored. The app keeps macOS 14 compatibility and Swift 5 language mode with complete concurrency checking. SwiftTerm remains pinned at 1.99.1.

| Command | Check |
| --- | --- |
| `make format` | Format Swift sources, tests and icon script using Xcode's `swift-format` |
| `make lint` | Strict formatting and style diagnostics |
| `make test` | Hostless XCTest bundle, Debug build, temporary state and repositories |
| `make build` | Release application build |
| `make check` | Lint, tests, Release build |
| `make install` | Install the build in Applications and move duplicate build/backup apps to Trash |
| `make run` | Install, clean up duplicates, then open the Applications copy |
| `make cleanup-installs` | Remove duplicate AgentDeck apps under `build/` after installation |

Xcode must include `swift-format` for lint/format. The Makefile uses Bash pipefail so a compiler failure cannot be hidden by the output tail.

For a local app update, increment the patch version in `project.yml`, build, then replace
`/Applications/AgentDeck.app` and quit/reopen AgentDeck. A successful `make build` alone leaves an already-running
installed app unchanged. Verify the installed bundle version and the visible feature after relaunch;
user state and browser profiles live outside the application bundle.

Keep only the latest verified `/Applications/AgentDeck.app`. Do not retain old installation `.app` backups.
The cleanup script checks bundle identity and refuses to discard a build newer than the installed version;
it moves matching duplicates to Trash, unregisters their app entries, and preserves other applications. Builds/tests can recreate Debug or
Release app bundles, so run cleanup again after validation and installation. This preference is also recorded
in the project's `AGENTS.md`. Saved sessions and browser profiles are not application bundles and stay in place.

Local acceptance on 0.1.7 confirmed visible tab strips in CLI mini-windows, ⌘T and the strip's **+** adding
another Codex instance to the same pane, and closing the extra tab without removing its siblings.

To enable the tracked pre-commit gate: `git config core.hooksPath .githooks`. The hook runs lint, format, tests and build. It is not installed automatically.

## Regression coverage

Tests cover malformed and fragmented HTTP requests, UTF-8 byte framing, origin/host checks, live loopback requests and listener shutdown, JSON-RPC and board actions, invalid ports, stopped-session injection, shell-template quoting, large stderr, Git worktree collisions/dirty deletion, failed recruit isolation, state round trips/corruption, status heuristics, actual PTY restart/exit and stale delayed Enter, and WebKit stop/render/restart with a local HTML page.

A browser-automation test drives a companion browser end to end on a `data:` page (navigate, read, click by text, type and submit, eval, screenshot from a parked view, removal with the owner) in a throwaway window. The test target lists production source files explicitly in `project.yml`; add new `Sources` files there.

Tests do not launch paid/provider agents or use existing login profiles. Browser tests create a fresh WebKit profile and request its deletion afterward. Saved AgentDeck state is never loaded by the hostless test target.

Tab tests cover legacy pane migration, per-pane selection persistence, shared geometry and canvas packing,
neighbor selection on close, maximized/sidebar navigation, and referenced-worktree protection. A native SwiftUI
terminal test uses disposable shell PTYs to verify hidden output, view detachment, keyboard focus and sibling
process retention when another tab closes.

CLI-profile tests record expanded launch arguments using shell-function stubs, including permission-bypass flags
and quoted MCP paths. They cover legacy command migration, custom-command retention and persisted opt-outs.

Browser-profile tests cover shared cookies, separate-account isolation, retention when a shared pane is removed,
profile restoration from saved state, and switching modes without starting a stopped pane. Shared sign-ins use
the profile ID persisted in settings. Old per-pane stores remain available through Separate account in the inspector.

Startup/skill tests additionally cover default pane composition and idempotence, persistence migration, corrupt-state startup, skill directory resolution, symlink cycles and deduplication, oversized/unreadable files, enabled/disabled MCP access, catalog exports and stale reload cancellation.

Settings → General can disable automatic defaults on an empty launch. Settings → Skills controls folders and enabled skills; use Reload after editing a skill. The generated catalog is at `~/Library/Application Support/AgentDeck/skills/catalog.md`. Missing agent commands display setup links; their authentication remains interactive.

## Manual acceptance still needed

- Authenticate each desired website; embedded WebKit OAuth restrictions are provider-specific.
- Exercise installed CLI versions, credentials, MCP setup and a real model turn.
- Check canvas dragging/resizing, keyboard shortcuts, theme and multi-window behavior interactively.
- Test on the oldest supported macOS version and Intel hardware; local verification uses the available Apple Silicon SDK/runtime.

If saved state cannot decode, back up and repair `~/Library/Application Support/AgentDeck/state.json`, then restart. Saving is disabled until restart to protect that file. App alerts report write errors.
