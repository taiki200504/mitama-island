import SwiftUI

/// Sound: whether it plays, how loud, which sound per moment, and when to stay
/// quiet regardless.
struct SoundSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var sound: SoundSettings { model.settings.sound }

    private var availableSounds: [String] { NotificationSoundService.availableSounds() }

    var body: some View {
        SettingsPane(tab: .sound) {
            outputSection
            themeSection
            raisedEventsSection
            unraisedEventsSection
            quietHoursSection
        }
    }

    // MARK: Output

    private var outputSection: some View {
        Section(lang.t("settings.sound.section.output")) {
            SettingsToggleRow(
                title: lang.t("settings.sound.enabled"),
                help: lang.t("settings.sound.enabled.help"),
                isOn: Binding(
                    get: { !sound.isMuted },
                    set: { sound.isMuted = !$0 }
                )
            )

            SettingsSliderRow(
                title: lang.t("settings.sound.volume"),
                value: Binding(get: { sound.volume }, set: { sound.volume = $0 }),
                range: 0...1,
                step: 0.05,
                defaultValue: SoundSettings.Defaults.volume
            ) { value in
                "\(Int((value * 100).rounded()))%"
            }
            .disabled(sound.isMuted)
        }
    }

    private var themeSection: some View {
        Section(lang.t("settings.sound.section.theme")) {
            SettingsRow(title: lang.t("settings.sound.theme")) {
                Text(lang.t("settings.sound.theme.system"))
                    .foregroundStyle(.secondary)
            }
            SettingsRow(
                title: lang.t("settings.sound.import"),
                availability: FeatureAvailability(.soundPackImport)
            )
        }
    }

    // MARK: Per-event assignment

    private var raisedEventsSection: some View {
        Section(lang.t("settings.sound.section.events")) {
            ForEach(NotificationSoundEvent.raisedEvents, id: \.self) { event in
                eventRow(event)
            }
        }
    }

    private var unraisedEventsSection: some View {
        Section {
            ForEach(NotificationSoundEvent.unraisedEvents, id: \.self) { event in
                eventRow(event, pendingNote: .unraisedSoundEvents)
            }
        } header: {
            Text(lang.t("settings.sound.section.eventsPending"))
        } footer: {
            Text(lang.t("settings.sound.eventsPending.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func eventRow(
        _ event: NotificationSoundEvent,
        pendingNote: PendingCapability? = nil
    ) -> some View {
        SettingsRow(title: lang.t(event.labelKey), pendingNote: pendingNote) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { sound.soundName(for: event) },
                    set: { sound.setSoundName($0, for: event) }
                )) {
                    ForEach(availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Button {
                    NotificationSoundService.play(sound.soundName(for: event), volume: sound.volume)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .help(lang.t("settings.sound.preview"))
            }
        }
    }

    // MARK: Quiet hours

    private var quietHoursSection: some View {
        Section(lang.t("settings.sound.section.quietHours")) {
            SettingsToggleRow(
                title: lang.t("settings.sound.quietHours.enabled"),
                help: lang.t("settings.sound.quietHours.help"),
                isOn: Binding(
                    get: { sound.quietHoursEnabled },
                    set: { sound.quietHoursEnabled = $0 }
                )
            )

            if sound.quietHoursEnabled {
                minuteRow(
                    title: lang.t("settings.sound.quietHours.start"),
                    minutes: Binding(
                        get: { sound.quietHoursStart },
                        set: { sound.quietHoursStart = $0 }
                    )
                )
                minuteRow(
                    title: lang.t("settings.sound.quietHours.end"),
                    minutes: Binding(
                        get: { sound.quietHoursEnd },
                        set: { sound.quietHoursEnd = $0 }
                    )
                )
            }
        }
    }

    /// Half-hour steps keep this to a short menu rather than a date picker that
    /// would tower over every other row in the pane.
    private func minuteRow(title: String, minutes: Binding<Int>) -> some View {
        SettingsRow(title: title) {
            Picker("", selection: minutes) {
                ForEach(Array(stride(from: 0, to: 24 * 60, by: 30)), id: \.self) { value in
                    Text(Self.clockLabel(value)).tag(value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    static func clockLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
