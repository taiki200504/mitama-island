# Closed-island modules: one body, one accessory

2026-09-07. Extends [peek-band-design.md](./peek-band-design.md) — the peek
band still exists as the closed island's way of saying who is waiting and for
how long; this is the layer that decides whether the peek band, a calendar
entry, or nothing at all gets to be the thing shown, and adds a second,
independent slot for a timer, now-playing, the camera, or the shelf.

## Problem

Everything the closed island might want to say — a waiting agent, an urgent
mitama alert, a calendar entry, a timer, what's playing, the camera watching,
the shelf having something on it — used to be a separate ad-hoc decision
scattered across `AppModel`. Nothing enforced an order between them, so two
features arriving at once had no defined winner, and a later module (a timer,
now-playing) had nowhere to plug in without re-deciding everything that came
before it.

## Design

The closed island shows **one body slot and one trailing accessory**, decided
by a single pure function of plain values — `IslandClosedArbiter.resolve(_:)`
in `OpenIslandCore`. Nothing EventKit-, AVFoundation-, or file-system-shaped
crosses into `OpenIslandCore`; `AppModel.islandClosedContent(now:)` is
responsible for turning its own live state into `IslandClosedInputs` first.

### Body priority

1. `urgent` — a mitama alert nobody has acted on. It lands in a database and
   says nothing on its own, unlike an agent, which already announced itself
   with a card.
2. `waiting` — the agent that has been waiting on you longest.
3. `eventStarted` — a calendar entry that started, shown only for the first
   **three minutes**. Past that it stops being news and starts being a
   countdown of how late the meeting already ran, so it disappears rather than
   turning into one.
4. `nextEvent` — what's next, only when `showsNextEvent` is on.

Nothing below the first non-nil case in that list is ever consulted — a
waiting agent can never lose the body slot to a calendar entry, no matter how
soon that entry starts.

### Accessory priority

1. `timer` — a running timer's remaining minutes.
2. `nowPlaying` — whether something is currently playing.
3. `cameraWatching` — the camera is open and waiting for the raised-palm
   gesture. macOS lights its own indicator for as long as that's true; this is
   the island's only way to say why.
4. `shelf` — the shelf has something on it (count > 0; an empty shelf is not
   an accessory).

The body and the accessory are resolved independently — an accessory never
changes which body wins, and vice versa.

### Width: the accessory gives way first

`IslandClosedContent.intrinsicWidth(layout:maxWidth:)` (App-side, in
`Views/V6NotchContent.swift`) computes the body's width and the accessory's
width separately. If showing both would push the pill past
`physicalNotchWidth + 2×33` (the same bleed
`OverlayPanelController.closedPillSideBleed` already reserves on each side),
the accessory is dropped and the body renders alone. The body — whatever is
actually waiting on you — is never the one that gives way.

### Rendering

`SAOPeekGaugeView` replaced the old `V6PeekBandView`: a small diamond, the
label (a fixed English agent name or a clock time — never localized, matching
the crystal-HUD grammar's own display face), a 44×6 `SAOGaugeShape` gauge, the
elapsed/upcoming reading, and — when there are others behind this one — a
`SAOBlockStrip` tail that breathes statusYellow for "still waiting" and sits
dim for "just ahead in line". `SAOPeekGauge.level(elapsed:)` and
`levelForUpcoming(minutesUntil:)` are the pure functions behind the gauge's
fraction and tint; `SAOPeekGaugeTests` covers their boundaries.

## Sneak peeks: a temporary override, not a new surface

`IslandSneakPeek` (`OpenIslandCore`) is a short-lived message that replaces
the peek gauge for a few seconds without growing the island or changing its
width beyond the existing pop bonus. `IslandSneakPeekKind`'s raw value is a
priority order:

| Kind | Duration | Note |
|---|---|---|
| `shelf` | 1.2s | The old drop-on-the-island "pop". Empty text keeps the old scale-only behaviour. |
| `trackChanged` | 1.8s | |
| `eventStarting` | 4s | |
| `timerDone` | 4s | The one kind that gets a second try — see below. |
| `lockScan` | 2.2s | |
| `hudGauge` | 1.2s | Highest priority: interrupts everything. |

`IslandSneakPeekPolicy.replace(current:with:now:)` decides who wins: a higher
kind (or an equal one) always replaces what's showing; a lower kind is
dropped while a higher one is still active. `timerDone` is the exception —
losing the announcement that a timer someone set actually finished is a worse
trade than making it wait a couple of seconds, so `OverlayUICoordinator` keeps
one dropped or interrupted `timerDone` in a pending slot and re-offers it once
whatever beat it expires. Only one pending slot exists; a second `timerDone`
before the first gets its turn replaces the pending one rather than queuing
both.

`OverlayUICoordinator.presentSneakPeek(_:)` is the only way onto the island:
it's a no-op unless the island is actually closed and quiet enough to show
something (the same `shouldStayQuiet` gate a notification would have to
clear). `notchPop()` now routes through it with an empty-text `.shelf` peek,
which is why dropping a file on the closed island still looks exactly like it
always did.

## The `IslandClosedInputs` contract for later modules

A timer, now-playing, calendar-entry-started, lock-scan, and HUD-gauge module
each plug into this the same way: turn their own live state into one or more
fields on `IslandClosedInputs`, or into an `IslandSneakPeek` for a temporary
announcement. None of them need to know about each other, and none of them
need to touch `IslandClosedArbiter` — the priority order already accounts for
where they land.

- **Timer** — `IslandClosedInputs.timer` (remaining minutes + label) for the
  accessory; a `timerDone` sneak peek when it finishes.
- **Now playing** — `IslandClosedInputs.nowPlayingIsPlaying` for the
  accessory; a `trackChanged` sneak peek when the track changes.
- **Calendar (event started)** — `IslandClosedInputs.eventStarted` for the
  body; an `eventStarting` sneak peek at the moment it begins.
- **Lock scan** — a `lockScan` sneak peek only; it has no accessory or body
  state to carry between screens.
- **HUD gauge** — a `hudGauge` sneak peek with `gauge` set; same as above.

No accessory or body case exists for "remaining minutes of an in-progress
event" — once `eventStarted`'s three-minute window passes, the event has
nothing left to say until `nextEvent` picks up the next thing on the
calendar.

## Clipboard

2026-09-08. Fills in `IslandSurface.clipboard`, previously a bare-title
placeholder like `.nowPlaying` still is.

`OpenIslandCore.ClipboardItem` / `ClipboardLedger` are the pure rules — the
same shape `Shelf.swift` uses for the shelf: a value type per entry, and a
namespace of static functions (`inserting(_:into:)`, `removing(id:from:)`)
that decide what the list looks like next, with nothing macOS-shaped in
sight. Deduping by `contentHash` moves a repeat copy back to the top instead
of stacking an identical row underneath the one already there; the ledger
caps at 50 items and 20MB, oldest first to go.

`PasteboardWatcher` (App) polls `NSPasteboard.general.changeCount` every
0.5s — AppKit has never offered a change notification, since anything on the
machine can write to the pasteboard at any moment — and turns a new value
into a `ClipboardItem`: `.text`, `.image` (PNG plus a small thumbnail), or
`.fileURLs`. Before it does, `ClipboardPrivacy.shouldSkip` gets a veto: a
locked screen, the `org.nspasteboard.*` UTIs well-behaved password managers
tag a secret copy with, or a bundle identifier on a small built-in deny list
(1Password, Bitwarden, Keychain Access, KeePassXC) all mean the copy is never
turned into an item at all, not merely hidden later.

`ClipboardStore` (App, `@Observable`) holds the in-memory list and, only
when `ClipboardSettings.persistsToDisk` is on, a `ledger.json` under
`Application Support/MitamaIsland/Clipboard` — text and file paths live
inline in that file, an image's PNG and thumbnail go into their own blob
files next to it, the same "small ledger, larger payloads elsewhere" split
`ShelfStore` uses for real files. `ClipboardSettings.enabled` gates the
watcher itself and defaults off: nothing is recorded, on disk or in memory,
until the setting is switched on.

Picking a row in the opened surface calls `AppModel.selectClipboardItem`,
which copies the item back to the general pasteboard and — only with
`ClipboardSettings.pastesOnSelect` on and Accessibility actually granted —
posts a synthetic ⌘V to whatever app is frontmost. `ClipboardStore` tells the
watcher about every write it makes back to the pasteboard so a copy the
store itself performed is never re-recorded as a new external one.

## System HUD: answering volume and brightness keys ourselves

2026-09-08. The first module to actually use the `hudGauge` sneak peek the
table above already reserved a row for.

### Mechanism

`SystemKeyTap` installs a `CGEvent` tap on the system-defined event stream
(`NX_SYSDEFINED`, decoded by `SystemKeyEvent` in `OpenIslandCore`) and
returns `nil` from the callback for a key it takes over — that `nil` is the
entire suppression mechanism, since it is what stops macOS from ever drawing
its own on-screen display for that key. The tap needs Accessibility
(`AXIsProcessTrusted`) and dies with the process: revoke the permission or
quit the app and the next press reaches macOS unchanged, there is no state
where a key goes permanently silent.

Volume and mute go through public CoreAudio (`AudioOutputControl`): the
default output device's `kAudioDevicePropertyVolumeScalar` and
`kAudioDevicePropertyMute`, main element with a per-channel fallback for
interfaces that only expose that. Brightness (`DisplayBrightnessControl`) and
the keyboard backlight (`KeyboardBacklightControl`) have no public API at
all — every third-party brightness tool on macOS resorts to the same private
`DisplayServices` and `CoreBrightness` frameworks this does, loaded via
`dlopen`/`dlsym` and the Objective-C runtime rather than linked directly.

**Fails open.** If a private symbol cannot be found, that backend's
`isAvailable` is `false`, and `SystemHUDCoordinator` never swallows a key
whose backend does not work — the key reaches macOS unchanged and its own
OSD shows for it, rather than the app taking over a key it cannot actually
act on. `HUDStepper` (`OpenIslandCore`) is the pure stepping grid every press
moves along: 1/16 of the range per plain press, 1/64 with ⌥⇧ held, matching
macOS's own two granularities for these keys.

### What it does not cover

Control Center's own sliders, AirPods' volume, the Touch Bar, and an
external display's own on-screen controls are outside what a system-defined
key event or these private frameworks can reach — those still show macOS's
own display no matter how this feature is configured.

### Settings

Everything lives behind `HUDSettings.replacesSystem`, off by default:
turning it on is the one place that asks for Accessibility
(`AXIsProcessTrustedWithOptions` with the prompt option), and every other
switch in the group — per-meter enable, the keyboard backlight, the feedback
sound — only matters once it is. The keyboard backlight stays opt-in even
with the master switch on, being the meter most likely to shift between
macOS versions.

## What this PR does not do

- No real now-playing or lock-scan feature exists yet. `AppModel` exposes
  `debugClosedAccessoryTimer` and the `IslandDebugScenario.closedAccessoryTimer`
  / `.sneakPeekPop` harness fixtures purely to exercise the accessory and the
  sneak-peek override ahead of those modules landing.
- `IslandSurface.nowPlaying` still exists as an opened-content placeholder (a
  bare `saoCaps` title) so the surface is reachable; its real content is a
  later PR.
