import Foundation

/// The engine capability a setting needs before it can honestly be switched on.
///
/// The settings surface is built ahead of the behaviour it controls, so a toggle
/// can exist with nothing behind it. Rather than shipping a switch that silently
/// does nothing, every such control declares the capability it waits on and is
/// rendered disabled with a "not wired up yet" note until that capability lands.
///
/// `implemented` is the single ledger. Landing a capability means adding it to
/// that set — every control waiting on it becomes live in the same commit, and
/// nothing else has to be remembered.
enum PendingCapability: String, CaseIterable, Sendable {
    // Panel visibility and dismissal
    case fullscreenDetection
    case foregroundTerminalDetection
    case autoHideTimer
    case outsideClickDetection

    // Notification routing

    // Quiet scenes
    case focusModeDetection
    case screenStateDetection
    case screenCaptureDetection

    // Keyboard
    case globalHotkey
    case switcherPanel
    case panelKeyHandling

    // Sound
    case soundPackImport
    case unraisedSoundEvents

    // Notification filters

    // Usage

    // Agent integrations
    case approvalRouting
    case sessionAutoNaming
    case memoryWatchdog

    // Panel presentation
    case completionCardSizing
    case notchCalibration
    case reasoningEffortMetadata

    // Shell

    /// Capabilities whose engine support has actually landed.
    ///
    /// Add a case the moment its behaviour ships, never in advance.
    static let implemented: Set<PendingCapability> = [
        .foregroundTerminalDetection,
        .outsideClickDetection,
        .fullscreenDetection,
        .autoHideTimer,
        .focusModeDetection,
        .screenStateDetection,
        .screenCaptureDetection,
        .notchCalibration,
        .completionCardSizing,
    ]

    var isImplemented: Bool { Self.implemented.contains(self) }

    /// Localization key for the short explanation shown next to a disabled control.
    var explanationKey: String { "settings.pending.\(rawValue)" }
}

/// Whether a given settings control can be interacted with.
enum FeatureAvailability: Equatable, Sendable {
    case ready
    case pending(PendingCapability)
    /// Built, but this Mac cannot supply the signal it needs — a Focus database
    /// macOS will not hand over, for instance. Distinct from `pending`: waiting
    /// for a future version would be a lie, so the note says why instead.
    case unsupported(reasonKey: String)

    init(_ capability: PendingCapability) {
        self = capability.isImplemented ? .ready : .pending(capability)
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Localization key for the note shown when the control is unusable here.
    var unsupportedReasonKey: String? {
        if case let .unsupported(key) = self { return key }
        return nil
    }

    var pendingCapability: PendingCapability? {
        if case let .pending(capability) = self { return capability }
        return nil
    }
}
