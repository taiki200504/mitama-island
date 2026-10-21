# Ambient live transcription

The standing microphone optionally transcribes Japanese on-device with macOS 26
SpeechAnalyzer / SpeechTranscriber. The preference defaults to enabled independently
of the existing standing-microphone opt-in. No model downloads or permission
prompts are initiated here. Unsupported systems, missing installed assets, or
missing speech authorization disable recognition while WAV capture continues.

SegmentWriter feeds a copy of the existing tap buffer after its WAV write. Each
WAV has its own recognition stream. The shared AudioConverterBox converts that
stream into the analyzer's compatible format. Muting, silence, the duration cap,
and engine teardown finish the stream, finalize the analyzer, then flush final
results. Switching live transcription off finishes only recognition, keeping the
WAV recording open. Voice-command sessions still own separate converter instances.

Only final results enter LiveTextBlock. Every 45 seconds, a block containing at
least eight characters is published; shorter fragments remain for
the next block and are discarded if still short when the recording ends. Files
are exclusively written under ~/.mitama/earshot/live-in with UTC timestamps and
an eight-hex UUID prefix. Each has a start/end/audio header and plain text body.
A private 0600 temporary file is closed before a same-directory atomic rename.
Failed publication retains the block for the next attempt. Temporary files are
removed on failure.

Input queues retain the newest 64 buffers to keep memory bounded if recognition
falls behind. Each instance's converter has a single sequential consumer. The
microphone tap is never installed twice. Actual microphone recognition requires
manual verification on a supported Mac with Japanese speech assets installed.

## Validation

- Serialized `swift build` succeeded (43.46 seconds), under the `heavy` lock.
- `heavy swift test --filter LiveTextBlockTests` succeeded: five tests,
  covering short-block retention, blank results, headers, the exact minimum,
  preference defaults/persistence, and UTC filenames.
- `git diff --check` passed; all four modified localization files passed
  `plutil -lint`.
- Existing tests were not modified. No microphone or recognition engine was
  invoked by the added tests. Real-device recognition remains unverified as
  agreed in the task. No commit or push was performed.

## Changed files

- `Sources/OpenIslandApp/Voice/AmbientLiveTranscription.swift`
- `Sources/OpenIslandApp/Voice/AmbientListenSession.swift`
- `Sources/OpenIslandApp/Voice/VoiceCommandSession.swift` (shared converter visibility/comment only)
- `Sources/OpenIslandApp/Settings/AmbientListenSettings.swift`
- `Sources/OpenIslandApp/Views/Settings/Panes/ShortcutsSettingsPane.swift`
- `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings`
- `Sources/OpenIslandApp/Resources/ja.lproj/Localizable.strings`
- `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/OpenIslandApp/Resources/zh-Hant.lproj/Localizable.strings`
- `Tests/OpenIslandAppTests/LiveTextBlockTests.swift`
- `docs/live-transcription.md`
