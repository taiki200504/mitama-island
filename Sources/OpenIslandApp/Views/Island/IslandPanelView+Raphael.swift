import OpenIslandCore
import SwiftUI

/// The Raphael companion's switch, in the opened island's header.
///
/// The status-bar menu has the same items, but on a notched MacBook with a full
/// menu bar the status item is often hidden behind the notch — measured
/// 2026-10-06, the icon was not visible at all. The island header is always reachable.
extension IslandPanelView {
    var raphaelHeaderMenu: some View {
        let status = model.raphaelStatus
        return Menu {
            if let status {
                Toggle(model.lang.t("statusItem.raphael.enable"), isOn: raphaelBinding(status.enabled) { on in
                    on ? await RaphaelControl.enable() : await RaphaelControl.disable()
                })
                // mitama-os 版では旧 raphaelctl の on/off が旧アプリへ書き戻すので押せなくする。
                .disabled(!status.canSwitchOnOff)
                Toggle(model.lang.t("statusItem.raphael.micMute"), isOn: raphaelBinding(!status.mic) { muted in
                    muted ? await RaphaelControl.muteMicrophone() : await RaphaelControl.unmuteMicrophone()
                })
                Toggle(model.lang.t("statusItem.raphael.voiceMute"), isOn: raphaelBinding(!status.voice) { muted in
                    muted ? await RaphaelControl.muteVoice() : await RaphaelControl.unmuteVoice()
                })
            } else {
                Text(model.lang.t("statusItem.raphael.notInstalled"))
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.islandText(size: 10, weight: .semibold))
                .foregroundStyle(
                    status?.enabled == true
                        ? SAOGrammar.Palette.accentOrange
                        : V6Palette.paper.opacity(0.62)
                )
                .frame(width: Self.headerControlButtonSize, height: Self.headerControlButtonSize)
                .background(V6Palette.paper.opacity(0.08), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(model.lang.t("statusItem.raphael"))
        .help(model.lang.t("statusItem.raphael"))
        .task { model.raphaelStatus = await RaphaelControl.fetchStatus() }
    }

    private func raphaelBinding(_ value: Bool, apply: @escaping (Bool) async -> Void) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { newValue in
                Task { @MainActor in
                    await apply(newValue)
                    model.raphaelStatus = await RaphaelControl.fetchStatus()
                }
            }
        )
    }
}
