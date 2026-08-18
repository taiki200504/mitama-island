import Foundation
import IOKit
import OpenIslandCore
import IOKit.ps

/// 安全弁の入力を集めるだけの層。判定はしない。
///
/// Hub（`Gugen/inbox/Hub` の `macos/HubIsland`）から持ち込んだ。あちらは
/// スリープを抑止するために使っていて、こちらはカメラを開けておいてよいか
/// の判定に使う。読み取る対象が同じなので、書き直す理由が無い。
///
/// 電源と電池は同期読みが安いので、[WakeGuard] の評価タイミングで読み直す。
/// C コールバック(IOPSNotificationCreateRunLoopSource)を張っても、結局
/// 評価は定期的に回すので、増える failure mode に見合わない。
/// 熱と低電力モードだけは通知が用意されているので素直にそれを使う。
@MainActor
@Observable
final class PowerMonitor {
    /// 電源に繋がっているか。電池を積んでいない Mac では常に true
    private(set) var isOnAC = true
    /// 電池残量(%)。電池が無ければ nil
    private(set) var batteryPercent: Int?
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    /// 蓋が閉じているか。表示と記録にだけ使う(判定には使わない)
    private(set) var isLidClosed = false

    /// Fires when the thermal state or low-power mode changes, so a decision
    /// made minutes ago can be revisited without a timer.
    var onChange: (() -> Void)?

    /// The reading, in the shape the policy takes.
    var conditions: CameraPowerPolicy.Conditions {
        .init(
            isOnAC: isOnAC,
            batteryPercent: batteryPercent,
            isLowPowerMode: isLowPowerMode,
            thermalState: thermalState,
            isLidClosed: isLidClosed
        )
    }

    private var observers: [NSObjectProtocol] = []

    func start() {
        refresh()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.thermalState = ProcessInfo.processInfo.thermalState
                self?.onChange?()
            }
        })
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.onChange?()
            }
        })
    }

    func stop() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    /// 電源・電池・蓋を読み直す。IOKit の同期読みだけなので数百マイクロ秒で終わる
    func refresh() {
        readPowerSource()
        isLidClosed = Self.readClamshellClosed()
        // 通知を取りこぼしていても、ここで必ず現在値へ寄せる
        thermalState = ProcessInfo.processInfo.thermalState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func readPowerSource() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            // 内蔵電池以外(UPS など)を混ぜない
            guard desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                isOnAC = state == kIOPSACPowerValue
            }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            {
                batteryPercent = Int((Double(current) / Double(max) * 100).rounded())
            }
            return
        }
        // 内蔵電池が見つからない = デスクトップ。電池由来の安全弁は効かせない
        batteryPercent = nil
        isOnAC = true
    }

    /// IOPMrootDomain の AppleClamshellState。蓋の無い Mac では存在しないので false 扱い
    private static func readClamshellClosed() -> Bool {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IOPMrootDomain")
        guard entry != MACH_PORT_NULL else { return false }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(
            entry, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else { return false }
        return value
    }
}
