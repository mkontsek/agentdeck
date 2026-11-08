# Connected mini-windows

Each subagent has an independent movable/resizable AgentDeck mini-window. Its browser tabs live inside that window, alongside its terminal. Terminal/browser split mode is the default; wide windows show both side by side and compact windows stack them. Window actions → Split terminal and browser switches back to single-tab presentation and persists per owner. Ordinary agents retain their existing tab groups; browser ownership remains per agent.

```text
Main [Terminal | Browser tabs] ──┐
                                └──→ Worker [Terminal | Browser tabs]
```

## Layout and text

- Startup opens Sessions and fits all mini-windows into the measured canvas, including windows saved off-screen. The fit runs once per launch. Later manual positions/sizes remain until the next launch or explicit Fill Canvas.
- Drag the title/grip; resize from the bottom-right grip; double-click the top bar to fill the canvas and double-click again to restore the saved position/size. Window actions also offers movement, size presets and maximize/restore. Compact windows keep a small header and one visible tab row so content retains space.
- Terminal text grows/shrinks with displayed window dimensions, including maximize and grid. Browsers instead fit the page width by default, retaining vertical scrolling; an explicit zoom override stays fixed across navigation and resizing. The base font refers to a normal 640×440 window. Automatic fonts stop at the configured global size (minimum 5 points), with half-point steps below that ceiling. Returning to an earlier window size restores its earlier small font; shrinking further reduces it again. Manual overrides may exceed the global size, up to 40 points.
- `−`/`+` or Cmd+ / Cmd− pins a manual size for that session. Window actions → Scale text with window, the inspector’s Automatic button, or Cmd0 clears it. Existing overrides survive startup fitting and restoration.
- Connections use antialiased right-angle bends with a 4-point radius and filled arrowheads. Routes prefer a 12-point gutter beside mini-windows, approaching the border only to attach at their endpoints. Tight layouts fall back to a compact visible route. They render above borders without intercepting input. Fully covered endpoints cannot have a visible route; exceptionally large searches (over 128 obstacles or 16,384 grid nodes) are also omitted to keep input responsive; move the covering window or use the relationship buttons. Settings → General → Appearance → Canvas arrows changes the persisted arrow color independently of the focus border. Named relationship buttons provide equivalent navigation. Parent→worker lines remain visible when the worker shows a browser tab.

## Browser tabs and identity

- Browser creation preserves focus. Select a browser tab or the Browser relationship control to focus it; the terminal stays visible in split mode. Select the terminal tab to return keyboard focus. Browser + and Cmd-T while viewing a browser create another browser tab for that owner.
- `selectedBrowserTabs` remembers each owner’s browser selection even while its terminal or another owner’s browser is displayed. Automation first filters by owner UUID, then resolves that owner’s remembered selection.
- Migration separates legacy nested workers and folds standalone owned-browser panes into their agent windows. Session IDs, parent/task ownership, worktrees, provider checkpoints, URLs and shared/isolated profile IDs remain unchanged. Reapplying migration is a no-op. Standalone user browser windows remain independent.
- Closing a parent promotes surviving workers; closing an owner removes only its owned browser tabs. Closing one browser tab retains its siblings. Shared sign-ins do not grant another agent access to a browser tab.

## Demo screenshots

The toolbar’s **Demo mode** toggle covers every mini-window with opaque synthetic text and example browser content. Real names, URLs, paths, stats and task text are not used by the demo views. Sidebars, the board, inspector, usage and log panels are hidden for the screenshot; their preferences remain unchanged. Live native content is inaccessible to pointer/keyboard input while masked. Existing processes and browser controllers keep running. Toggle off to restore the live view and focus. Demo mode is temporary and is off on launch. It masks the AgentDeck main window, not separate browser popup windows or other applications.

## Rendering and verification

Native focus changes follow explicit pane selection or real pointer/Tab navigation. Late terminal/browser attachment cannot replace an existing editor. A responder-boundary guard rejects WebKit autofocus before AppKit resigns the active editor, including selected pages trying to take a separate URL/text field. No draft or selection is inspected or copied. Worker coordination remains in the durable inbox from task79; task60 negotiated paste/Enter remains exclusive to explicit user input.

The canvas retains background terminals’ last painted layer while scrolling or typing. Parsing and input continue; focused text stays live. When scrolling settles, visible panes repaint their newest screen. Off-screen panes resume painting when revealed. No terminal is hidden/recreated and no output bytes are discarded. Changing provider titles/program metadata are coalesced into one workspace publication per 100 ms; native output and input do not wait for that presentation queue. Queued metadata is bound to the terminal identity and generation and discarded on stop/replacement/shutdown.

Native fixtures cover twenty-window startup fit, proportional font sizes and fixed overrides, browser page zoom and owner isolation, move/resize/maximize/tab switching, restoration, light/dark connectors and redraw catch-up. A twenty-PTY output-load fixture measures actual canvas scrolling and input echo with and without redraw deferral. Test state and profiles are disposable.

Installing replaces the bundle without restarting the active host. A user-scheduled relaunch activates startup fitting, browser-tab migration and rendering changes. Full external VoiceOver traversal and real provider restoration after relaunch remain manual acceptance items.
