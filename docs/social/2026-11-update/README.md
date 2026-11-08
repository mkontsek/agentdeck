# AgentDeck update animation

22-second silent, square H.264 MP4 at 1080×1080 / 30 fps. The same file accompanies either draft in [posts.md](posts.md). The illustration uses the app's canvas, mini-window, focus-border and rounded-connector vocabulary with invented tasks and content. It is deliberately labeled as an illustrated workflow; no real sessions, credentials, conversations or account data are captured.

Files:

- `agentdeck-update.mp4`: upload-ready animation.
- `poster.png`: cover image and static alternative.
- `render.swift`: deterministic AppKit/Core Graphics frame renderer, using only macOS system frameworks and the repository icon.
- `render.sh`: renders frames in a temporary directory and encodes them with an existing `ffmpeg` installation. No dependency installation or network access.
- `storyboard.csv`: timeline and transition intent.

Regenerate from the repository root on macOS:

```sh
bash docs/social/2026-11-update/render.sh
```

The four beats last 5.5, 6.5, 6 and 4 seconds (mean 5.5 seconds). Motion builds the relationships and separates worker updates from human input. Hard cuts change scale; smooth moves are confined to the canvas. No flashes, sound or private screenshots. Rendering does not launch AgentDeck or operate an existing session.
