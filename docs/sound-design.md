# Sound Design

Every sound the app makes — notifications, interface feedback, and the login
sequence — is a cue synthesised for this project, bundled under
`Sources/OpenIslandApp/Resources/Sounds/`. None of it is sampled from, or
derived from, any game, film, or product: see the legal note at the bottom.

## Cue catalog

| Event(s) | File | Duration | Character |
|---|---|---|---|
| `approvalNeeded`, `answerNeeded`, `eventStarting` | `ui-notify.caf` | 0.70s | A clear, attention-getting chime for something that needs a decision. |
| `taskComplete` | `ui-complete.caf` | 1.40s | A short resolving phrase — work finished. |
| `sessionStart` | `ui-link.caf` | 0.29s | A light connecting tone. |
| `contextLimit`, `usageAlmostFull`, `warning` | `ui-warning.caf` | 0.60s | A cautionary tone, distinct from the notify chime. |
| `islandOpenedByGesture`, `islandOpened` | `ui-open.caf` | 0.25s | A quick rising tick — the panel appearing. |
| `islandClosed` | `ui-close.caf` | 0.18s | The falling counterpart to `ui-open`. |
| `selection` | `ui-select.caf` | 0.12s | A soft tick for the switcher's highlight moving. |
| `confirm` | `ui-confirm.caf` | 0.35s | Submitting an answer or a reply. |
| `approve` | `ui-approve.caf` | 0.40s | Allow / Allow All. |
| `reject` | `ui-reject.caf` | 0.30s | Deny / Deny All. |
| `timerFinished` | `ui-timer-end.caf` | 1.60s | Reserved; not raised yet. |
| `lockScan` | `ui-lock-scan.caf` | 0.90s | Reserved; not raised yet. |
| `unlock` | `ui-unlock.caf` | 0.39s | Reserved; not raised yet. |
| — | `ui-hover.caf` | 0.06s | Bundled but not wired to anything — a menu-bar-resident app should not chime on every pointer pass. |
| — | `ui-urgent.caf` | 1.20s | Bundled for future use; not yet assigned a default. |
| login sequence: rise | `ui-linkstart-rise.caf` | 1.20s (stereo) | The light arriving, at the very start. |
| login sequence: tick × 5 | `ui-linkstart-tick.caf` | 0.15s | One per sense confirmed. |
| login sequence: resolve | `ui-linkstart-resolve.caf` | 1.80s (stereo) | The checklist giving way to identity. |

The login-sequence timing comes from `LinkstartSequence.cueSchedule`
(`Sources/OpenIslandCore/LinkstartSequence.swift`), derived from the same
phase durations the boot-sequence view draws from — the sound and the picture
cannot drift apart.

## Format

- Every short cue: CAF container, LPCM 16-bit, 48kHz, mono.
- The three `ui-linkstart-*` stems: same container and rate, stereo.

## Regenerating

```bash
python3 scripts/build-sounds.py --out Sources/OpenIslandApp/Resources/Sounds
```

Requires `numpy`, `scipy`, and `/usr/bin/afconvert` (both present on a normal
dev Mac). Pass `--only <cue-name>` to rebuild a single file, or `--check` to
verify the output without writing anything. Every waveform is generated
procedurally — sine and FM partials, filtered noise, a simple convolution
reverb — nothing is recorded or sampled.

## Override precedence

`NotificationSoundService.play(_:volume:)` resolves a name in this order:

1. A file the user imported through **Settings → Sound → Import a sound
   pack** (`CustomSoundLibrary`), matched by file stem.
2. A bundled cue under `Resources/Sounds/`.
3. A macOS system sound of the same name (`NSSound(named:)`), for anyone
   still assigned one of the old defaults (Glass, Hero, Tink, Submarine).

`scripts/check-sound-catalog.sh` fails the build if a cue name referenced in
code ships no file, or a shipped file is referenced nowhere.

## Legal note

All effects are synthesised procedurally from sine/noise primitives in this
repository; nothing is sampled from any game, film, or product.
