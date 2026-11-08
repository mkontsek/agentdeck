# Roadmap

## Phone companion and speech input — deferred

Requested 2026-10-30. Keep AgentDeck and its CLI/browser sessions on the Mac;
provide a phone-friendly companion for both iPhone and Android.

- Start with a mobile web app: sessions, readable output, task/approval inbox,
  and a prompt composer with transcript review before sending.
- Use phone keyboard dictation first. Add microphone recording and optional
  Mac-local whisper.cpp transcription later; consider native mobile apps only
  if on-device transcription or deeper OS integration warrants them.
- Add an authenticated, paired human-control API. Keep the existing local MCP
  endpoint private; it is not a remote-authentication boundary.
- Evaluate private connectivity through Tailscale. The host Mac must remain
  online; desktop agents do not move onto the phone.

This is roadmap work, not part of the current desktop release.
