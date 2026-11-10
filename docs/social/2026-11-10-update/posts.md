# AgentDeck update — social drafts

Prepared after the 0.1.34 source push, commit `df2b368dad84193d64a4a83f356a1b9db8b8fa23`. Text only; not published or scheduled. The previous animation and poster remain unchanged and do not demonstrate these latest features.

## X

AgentDeck update: glass balls open on click, with arrows that stay attached as windows expand. The canvas map now drags reliably, status colors match, and Up/Down + Return work in the Sessions sidebar.

Small fixes for a busy multi-agent workspace. Link below ↓

### Follow-up reply

AgentDeck → https://github.com/mkontsek/agentdeck

Open source under MIT, for macOS 14+. Source, setup instructions and the latest changes are in the repo.

## LinkedIn

When several coding agents are working, I want to see which conversation needs attention and move between them without losing my place.

I've been improving that part of AgentDeck, my open-source macOS workspace for AI agents.

With Glass balls enabled, unfocused worker windows collapse into small status balls. Click one to reopen its window. The arrows now touch the balls and stay in place through a slower expansion and collapse.

The canvas map lets me drag the viewport to reach windows off screen while keeping keyboard focus where I was typing. I've also fixed a drag that could release unexpectedly.

Status colors now agree across the balls and session indicators: yellow means attention, blue means working, green means finished, and gray means idle. In the Sessions sidebar, Up/Down keeps moving through the list; Return focuses the selected terminal or browser.

Source and setup instructions are in the first comment.

### Follow-up comment

AgentDeck: https://github.com/mkontsek/agentdeck

Free and open source under MIT. Native Swift/SwiftUI, macOS 14+. The README covers setup and how background coordination works.

## Publication notes

- Copy reflects the verified 0.1.33 arrow/motion/map corrections and 0.1.34 status/sidebar update. Local install preserves running sessions; the new code activates on relaunch.
- Arrow stability refers to ball/window transformations. Moving or resizing panes still recomputes routes; covered docks retain relationship navigation as a fallback.
- Status is derived from runtime signals and task state. Idle alone does not mean finished. Balls may pulse for attention; sidebar dots share their state and color without pulsing.
- Collapsing a window defers rendering; agents continue running. No provider-speed, cost-saving, forced-wake or exactly-once processing claim is intended.
- Post the link as the separate reply/comment. No new media is attached to these drafts.
