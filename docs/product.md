# Product Scope

## Problem

CLI coding agents are powerful, but they pull attention away from the editor and terminal. Developers need a lightweight control surface to monitor work, approve actions, answer questions, and return to the right session quickly — without handing their machine over to a closed-source paid app.

## Target User

- macOS developers using terminal-based coding agents daily
- Users running more than one agent or more than one terminal session
- Users who care about low latency, native behavior, and open-source transparency

## Product Principles

- **Open source** — all code is public, all contributions are AI-produced
- **Local first** — no server dependency, no accounts, no analytics
- **Native macOS** — SwiftUI + AppKit, not a web wrapper
- **Terminal-native** — built to support the terminal workflow, not replace it
- **Fail open** — if the app or bridge is unavailable, agents keep running unchanged

## Supported Agents, Terminals and IDEs

**The matrix lives in [README.md](../README.md)** — agents, terminals, IDEs, and how
far the jump-back goes for each. It was duplicated here and the copy drifted:
this file still called Warp "Planned" long after the precision jump shipped, and
never learned about Zellij, Cursor or the IDE column at all. One table, one place.

## Features

- **Notch overlay** — sits in the notch area on notch Macs, falls back to a compact top-center bar on external displays or non-notch Macs
- **Settings** — hook install/uninstall, usage dashboard, General, Display, Sound, Shortcuts, Lab, About
- **Notification mode** — auto-height panel for permission requests and session events
- **Notification sounds** — configurable system sounds with mute toggle
- **i18n** — English and Simplified Chinese
- **Session discovery** — auto-discover from local transcripts, persist across launches
- **Process discovery** — match active agents via `ps`/`lsof`
- **DMG packaging** — signing, notarization, GitHub Actions release workflow
- **Auto-update** — Sparkle-based automatic updates with appcast

## Island Utilities

The closed-island notch surface also hosts a small set of opt-in utilities
that reuse the same real estate as agent monitoring: now-playing controls, a
focus timer (with Pomodoro and eye-break modes), upcoming-calendar awareness,
a file shelf, clipboard history, and a system HUD that can replace the
volume/brightness key indicators. See
[docs/island-modules.md](./island-modules.md) for how they are prioritized
against each other and against agent events for the island's one body slot
and one accessory slot.

**Product boundary**: coding-agent monitoring is the primary job this app
does. The island utilities above are secondary — they exist because the
notch surface is already there, not because this app is becoming a
general-purpose menu-bar utility suite. Whenever a utility would compete with
agent monitoring for the same slot, agent monitoring wins (see the
body-priority order in docs/island-modules.md). Utilities that ship
default-off stay default-off.

## Success Criteria

- Agent events appear in the overlay with low latency
- Approval and answer actions round-trip back to the source process
- The app can restore focus to the owning terminal window reliably
- Idle resource usage remains low enough for all-day background use

## Future Directions

- Sound packs, themes, and onboarding polish
- Deeper terminal split targeting
