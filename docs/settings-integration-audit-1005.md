# Settings integration audit — 1005-island-settings

Baseline: db157bc. No builds or runtime grants performed by this worker.

## Confirmed and fixed

- `SilenceRule.firstPrompt` only read Claude metadata. Use the existing `AgentSession.initialUserPromptText`, which reads native metadata for all integrated agents. Regression coverage includes Claude, Codex rollout input with injected AGENTS instructions, and injected Claude task notifications.
- `AppModel.showCodexUsage` saved the toggle but only boot started the owner monitor. Toggling on now starts `HookInstallationCoordinator`'s monitor immediately; off cancels and resets it. Its 120-second cadence remains unchanged. A refresh-generation check prevents an in-flight load from restoring disabled usage. Enable/disable/re-enable regression prepared.
- Paseo sessions are deliberately excluded from Island auto-response rules. The existing settings footer now makes that exclusion explicit in all four supported languages.

## Settings ownership

`SettingsStore` groups share `PreferenceStore.standard` backed by the app's `UserDefaults.standard` domain. `PreferenceGroup` reads and writes through that store and its observation registrar. Views use the same model; search adds no setting store. AppModel retains system integration toggles (launch at login, usage visibility, ecosystem feed), applying side effects through owners. Native OS permission status remains separate from feature-enabled preferences.

Settings search preserves the twelve categories and current pane when filtering or clearing. It matches localized category labels plus category keywords. Empty matches are explicit. Sidebar and pane icons use one existing theme accent with reduced decoration; controls retain native semantics.

## Confirmed follow-up, not changed

Clipboard persistence off (`IslandSettingsPane` binding) only writes `clipboard.persistsToDisk`. `ClipboardStore.saveIfPersisting` then skips future saves but leaves the old ledger and image blobs. Turning persistence back on and relaunching can restore old entries. The feature-enabled off path already purges all data, but persistence-off does not. A separate user-reviewed policy is needed for preserving session memory while clearing or reversibly moving disk data. No clipboard content was read or removed.

## Verification handoff

`git diff --check` passes. Root owns build/test scheduling. Run app tests `NotificationFilterTests`, `CodexUsageSettingsTests`, and `SettingsSearchTests`, plus existing settings and usage tests. Verify sidebar search/clear/empty-result UI and live usage toggling in the integrated app before packaging. No full-access policy changes are included; previous live audits confirmed explicit full-access turns use `never` and `danger-full-access`.
