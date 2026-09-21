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
| `timerFinished` | `ui-timer-end.caf` | 1.60s | A countdown reaching zero (`FocusTimerCoordinator`). |
| `lockScan` | `ui-lock-scan.caf` | 0.90s | The lock-screen scan starting. |
| `unlock` | `ui-unlock.caf` | 0.39s | The scan finishing — the machine is yours again. |
| — | `ui-hover.caf` | 0.06s | Bundled but not wired to anything — a menu-bar-resident app should not chime on every pointer pass. |
| — | `ui-urgent.caf` | 1.20s | Bundled for future use; not yet assigned a default. |
| login sequence: rise | `ui-linkstart-rise.caf` | 1.20s (stereo) | Bright and airy — the light arriving. |
| login sequence: warp | `ui-linkstart-warp.caf` | 2.50s (stereo) | The dive: a rise that never tops out, thickening as it goes. |
| login sequence: flash | `ui-linkstart-flash.caf` | 1.80s (stereo) | Arrival — bright, not a boom. |
| login sequence: tick × 5 | `ui-linkstart-tick.caf` | 0.15s | One per sense confirmed. A narrow blip, not a bell. |
| login sequence: dive | `ui-linkstart-dive.caf` | 1.80s (stereo) | Leaving the interface — the second dive, into the white-out. |
| login sequence: resolve | `ui-linkstart-resolve.caf` | 1.80s (stereo) | Low and warm, fading out rather than landing on a chord. |

### Using your own audio for the login sequence

The five login cues are looked up in `~/Library/Application Support/MitamaIsland/Sounds/`
before the bundled ones, so a file named `ui-linkstart-rise.caf` (`.wav`,
`.m4a`, `.mp3`, `.aiff` also work) placed there wins without touching the app
or the repository.

```bash
zsh scripts/install-linkstart-audio.sh <your-recording> [offset-seconds]
zsh scripts/install-linkstart-audio.sh --restore      # back to the bundled cues
```

It slices one recording into the six cues at the sequence's own beats
(rise 0.00–1.40, warp 3.50–5.00, flash 5.00–5.80, tick 6.02–6.17, resolve
8.28–9.28, dive 16.60–18.40 — each overridable with `RISE_RANGE="0.0 1.5"` and
friends) and
writes them to that folder. **Whatever you put there stays there**: the folder
is outside the repository, nothing is committed, and the app ships only the
cues it synthesises itself.

### How the login cues are set

Nobody on this project can hear the cues being generated, so they are not set
by taste. `scripts/tune-linkstart.py` renders each cue across a grid of three
gains (body under 120 Hz, the 120–800 Hz middle, air above 3 kHz) and keeps
the combination whose spectrum lands closest to a measured target:

| cue | centroid | <120 Hz | >3 kHz |
|---|---|---|---|
| rise | 4,500 Hz | 3 % | 55 % |
| warp | 3,400 Hz | 8 % | 40 % |
| flash | 4,000 Hz | 7 % | 50 % |
| tick | 3,600 Hz | 1 % | 55 % |
| resolve | 2,100 Hz | 33 % | 24 % |

Those numbers were measured from a reference the owner supplied, analysed in
the browser so that only measurements — never audio — left the page. Re-run
`python3 scripts/tune-linkstart.py` after changing a cue's synthesis.

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
