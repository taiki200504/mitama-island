# Meeting auto-capture

mitama v3 §24 (F2 / F4). The island detects a meeting, records it, and hands
the files to mitama-os, which makes the notes. Nothing leaves the Mac from the
island; the hand-off is a folder move.

## Pieces

| Where | What |
|---|---|
| `OpenIslandCore/MeetingDetector.swift` | Pure state machine: `MeetingSignals` → `meetingStarted` / `meetingEnded` / `meetingSkipped`. Do-not-record list, company/personal tag. |
| `OpenIslandCore/MeetingCapture.swift` | Folder layout, `manifest.json` (`MeetingManifest`), inbox delivery (`MeetingInbox`), `summary.json` (`MeetingSummary`), UI phase. |
| `OpenIslandApp/Meeting/MeetingSignalSource.swift` | macOS: CoreAudio mic-in-use (per-process on 14.4+, excluding the island's own engines), NSWorkspace apps, browser window titles, calendar. |
| `OpenIslandApp/Meeting/MeetingRecorder.swift` | macOS: `AVAudioEngine` mic + ScreenCaptureKit app audio, two AAC files. |
| `OpenIslandApp/Meeting/MeetingCaptureCoordinator.swift` | Polls every 5 s, drives the recorder, stop/discard, hand-off, waits for the summary. |
| `OpenIslandApp/Views/Island/MeetingCaptureBar.swift` | 録音中 + 止める/捨てる, "making notes", summary card. The closed island shows a red dot + minutes (`IslandClosedAccessory.meetingRecording`). |

## Rules

- **Start**: microphone in use by another process AND one of: a known meeting app
  (Zoom, Teams, FaceTime, Webex, Slack huddle, Discord, Around, Tuple), a browser
  tab titled like Meet / Zoom / Teams / Webex, or a calendar entry now that has a
  call link. When macOS reports which process holds the mic (14.4+), the app must
  be that process (helpers count for their parent).
- **End**: mic idle for 60 s, or the meeting's app quits, or the person presses 止める.
- **Do-not-record**: Settings → Shortcuts → 会議の録音. One entry per line; matches app,
  bundle ID, title, calendar title or attendee (`@domain` works). Empty by default.
- **Company**: title keywords (default `Gugen`, `マカセタ`) or attendee domains tag the
  manifest `scope: "company"`. Still recorded; mitama-os routes the notes.
- No notice is sent to other participants (owner decision, 2026-11-24).
- Earshot (聞き書き) still pauses during calls; meeting capture is separate.

## Hand-off contract (island → mitama-os)

Recording folder (island-owned):

```
~/Library/Application Support/mitama/meetings/<id>/
    manifest.json        copy of the delivered manifest
    summary.json         written by mitama-os when the notes are done
```

Inbox (mitama-os-owned, configurable, default `~/.mitama/meetings/inbox/`):

```
<inbox>/<id>/            appears atomically (renamed from <inbox>/.<id>.partial/)
    <id>.mic.m4a         AAC, this person (may be absent)
    <id>.sys.m4a         AAC, everyone else (absent without Screen Recording)
    manifest.json        written last
```

`<id>` is the local start time `yyyyMMdd-HHmmss`, with `-2`, `-3`… on collision.
The pickup must ignore dot-names and folders without `manifest.json`, and owns
the audio from then on (retention `.3p.`).

`manifest.json` (`schema: "mitama.meeting.v1"`, dates ISO 8601 UTC, keys sorted):

```json
{
  "schema": "mitama.meeting.v1",
  "id": "20261124-153000",
  "started_at": "2026-11-24T06:30:00Z",
  "ended_at": "2026-11-24T07:05:12Z",
  "duration_seconds": 2112,
  "source": "app",                       // app | browser | calendar
  "app": { "bundle_id": "us.zoom.xos", "name": "zoom.us" },   // bundle_id may be absent
  "title": "Weekly with Sato",
  "scope": "personal",                   // personal | company
  "calendar": { "title": "...", "starts_at": "...", "ends_at": "...",
                "url": "https://...", "attendees": [] },     // absent when none
  "end_reason": "mic_idle",              // mic_idle | app_closed | user_stopped
  "files": { "mic": "20261124-153000.mic.m4a", "sys": "20261124-153000.sys.m4a" },
  "channels": { "mic": "self", "sys": "others" },
  "third_party": true,
  "recording_dir": "/Users/<me>/Library/Application Support/mitama/meetings/20261124-153000",
  "created_by": "mitama-island"
}
```

`summary.json`, written by mitama-os into `recording_dir` (write to a temp name,
then rename). Only `summary` is required:

```json
{
  "schema": "mitama.meeting.summary.v1",
  "id": "20261124-153000",
  "title": "Weekly with Sato",
  "summary": "…",
  "decisions": ["…"],
  "my_tasks": ["…"],
  "ai_requests": ["…"],
  "others_tasks": ["…"],
  "ideas": ["…"],
  "hub_url": "https://…",
  "generated_at": "2026-11-24T07:08:00.000Z"
}
```

The island polls for it every 15 s for two hours after the meeting ends.

## Not done yet

- F6 near-real-time captions (30 s, load-gated) — not implemented.
- On macOS < 14.4 the mic signal cannot exclude the island's own engines, so a
  recording there ends on app quit or 止める, not on mic idle.
