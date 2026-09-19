# Manus Integration Audit

**Date:** 2026-09-20  
**Scope:** Mapping mitama-island current implementation against Manus spec  
**Status:** Audit → Phased implementation plan

---

## Executive Summary

The island's closed-slot architecture (one body, one accessory, decided by `IslandClosedArbiter.resolve()`) already implements the **priority decision logic** that Manus requires. The spec's four modules can be adopted with minimal duplication:

- **Island Shell / Focus Card**: Needs new persistent storage for resumable work state (中断 marker)
- **Context Shelf**: Clipboard + shelf already exist; pinned items need addition
- **Calm Glance**: Partial (3 cities = "ambient time-of-day phase"; health signal ∅)
- **Quiet Desktop**: Conditional feature; straightforward to gate via HUD

**Key finding:** The spec's "one item at rest" (idle state) is already enforced by the closed-slot model — zero waste on the island when nothing is waiting. **Subtraction, not addition, is the design's first principle**, so this audit drops requirements that duplicate existing behavior and focuses on gaps.

---

## Requirements vs. Implementation Table

| Spec Module | Requirement | Current State | Gap | Decision |
|---|---|---|---|---|
| **Island Shell / Focus Card** | Manual "中断" saves resumable work state | ∅ | Need persistent `FocusCard` (work title, terminal target, snippet) | **PHASE 1** — Add after `SessionState` |
| **Island Shell / Resume Card** | On resume, show one minimal next action | Waiting agent + calendar entry shown | Gap: no context from previous interruption | **PHASE 1** — Restore context on app startup |
| **Island Shell / States** | Idle (one item) / Peek (hover reveal) / Act (explicit) | Idle: ✓ (arbiter enforces one body) | Peek & Act already exist (panel expand, jump target) | **Already covered** — Use existing surface |
| **Context Shelf** | Clipboard history | ✓ Merged (`ClipboardStore`, 50 items, 20MB) | ∅ | **Already covered** |
| **Context Shelf** | Pinned items (⌥-click in shelf) | Shelf expiry & removal ✓ | Gap: pin/favorite mechanism | **PHASE 2** — Shelf item metadata + UI |
| **Context Shelf** | File shelf (AirDrop, share sheet) | ✓ Merged (`ShelfStore`) | ∅ | **Already covered** |
| **Calm Glance** | 3 cities + time (scrollable/tappable) | Gradient backdrop (phase: dawn/day/dusk/night) | Gap: no multi-location display | **PHASE 3** — Ambient time zones |
| **Calm Glance** | 1 local health signal (battery, CPU, etc.) | System HUD (volume, brightness) ✓ | Gap: no proactive health metric (e.g. "Low Power Mode active") | **PHASE 3** — Health layer above HUD |
| **Quiet Desktop** | Hide desktop icons before screen share | ∅ | Gap: needs ScreenCaptureKit monitoring + icon visibility toggle | **PHASE 2** — Conditional desktop guard |

---

## Phased Implementation Plan

### Phase 1: Focus Card / Resume Card (Weeks 1–2)

**Goal:** User can manually save context during interruption; on resume, the island shows what they were working on.

#### 1.1 Add `FocusCard` to `OpenIslandCore`

```swift
public struct FocusCard: Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String                   // "Build manus-focus-card"
    public var snippet: String                 // Last 40–60 chars of code/prompt
    public var jumpTarget: JumpTarget?         // Terminal/Codex.app target
    public var savedAt: Date
    public var sessionID: String               // Source session for context
    
    public init(from session: AgentSession, snippet: String) { ... }
}

public struct FocusCardLedger: Sendable {
    public private(set) var current: FocusCard?
    
    public mutating func save(_ card: FocusCard) { ... }
    public mutating func clear() { ... }
}
```

**Location:** `Sources/OpenIslandCore/FocusCard.swift`  
**Tests:** `Tests/OpenIslandCoreTests/FocusCardTests.swift`

#### 1.2 Extend `SessionState` to hold `focusCard`

```swift
extension SessionState {
    public var focusCard: FocusCard?
    
    public mutating func saveFocusCard(_ card: FocusCard) {
        focusCard = card
    }
}
```

#### 1.3 Persist to `Application Support/MitamaIsland/FocusCard.json`

- Write on `SessionState.focusCard` change
- Load on app startup
- Expire if stale (>7 days at `focusCard.savedAt`)

#### 1.4 Add UI gesture: keyboard shortcut to save

- Global: ⇧⌘F (or settings-configurable)
- Shows **modal card** (non-intrusive) with pre-filled title + snippet + confirm
- Calls `AppModel.saveFocusCard()`

#### 1.5 On startup: show Resume Card in the idle board

- If `focusCard` exists and not stale, render it above the time-of-day clock
- Show title + snippet + "Jump" button
- Tapping jump calls `AppModel.jumpToSession(focusCard.jumpTarget)`
- Swiping/⎋ dismisses it; can be restored via a "Resume" shelf item

**Rationale:** The closed-island body slot is reserved for "what is waiting on you *now*" (agent, calendar). Resume context belongs in the **idle board**, not the closed pill — it's available on demand, not a standing interrupt.

---

### Phase 2: Conditional Desktop Guard + Shelf Pinning (Weeks 3–4)

#### 2.1 Quiet Desktop: Screen sharing detection

```swift
actor ScreenShareMonitor: Sendable {
    var isCapturingSuspect: Bool { 
        // ScreenCaptureKit.contentFilters for all active capture streams
    }
}

// In IslandClosedInputs
public var shouldHideDesktopIcons: Bool  // Gate from settings + ScreenShareMonitor
```

- Monitor `kCGSessionScreenIsLocked` and presence of active screen capture
- When either is true and `DisplaySettings.hidesDesktopIconsOnScreenShare` is on, set `NSAppearance.isDark = true` or call `Dock.setAutoHide(true)`
- Gate behind a **new setting** (off by default): "Hide desktop when screen sharing"

#### 2.2 Shelf item pinning

```swift
extension Shelf.Item {
    public var isPinned: Bool = false
    public var pinnedAt: Date?
}

extension ShelfStore {
    func togglePin(id: UUID) { ... }
}
```

- UI: ⌥-click → toggle star/pin icon on shelf row
- Persist to `ShelfStore`
- Pinned items float to the top; expire if unpinned and age exceeds threshold

---

### Phase 3: Calm Glance (Weeks 5–6)

#### 3.1 Multi-location time display

```swift
public struct CalendarLocation: Equatable, Codable, Sendable {
    public var city: String
    public var timezone: TimeZone
    public var offset: Int { ... }  // UTC hours
}

extension AmbientBackdrop {
    case timeZones([CalendarLocation])  // Replaces/augments gradient
}
```

- Settings: add 3 timezone picker (e.g., "San Francisco", "London", "Tokyo")
- Idle board: replace gradient with scrollable/tappable time cards
- Each card shows city name + local time + phase dot (dawn/day/dusk/night)
- Sync with `ambientBoardShowsTimeZones` setting

#### 3.2 Health layer (System + macOS OS signals)

```swift
public enum HealthSignal: Equatable, Codable, Sendable {
    case lowPowerMode(remainingMinutes: Int)
    case thermalPressure(level: ProcessInfo.ThermalState)
    case storageWarning(percentFull: Int)
}

extension IslandClosedInputs {
    public var healthSignals: [HealthSignal] = []
}
```

- Accessible via `ProcessInfo.thermalState`, `NSBatteryLevelDidChangeNotification`, `NSProcessInfoThermalStateDidChangeNotification`
- Display as a subtle gauge above system HUD (only when critical or user opts in)
- Use existing `HUDSettings.replacesSystem` gate; wrap new health metrics behind `DisplaySettings.showsHealthIndicators`

---

## What Was Deliberately Dropped & Why

| Feature | Reason |
|---|---|
| **Double-slot layout** (body + two accessories) | Island width is fixed at `notchWidth + 66pt bleed`. Arbiter's single accessory enforces priority; a second one would require dropping the body (the thing waiting on you). Subtraction is intentional. |
| **Floating context widgets** (clipboard, weather, stock ticker inline) | The closed pill is **quiet by design** — one thing at a time. Context is available in the idle board (no interruption cost) and full panel (swipe/click). Inline clutter contradicts the spec's "after interruption" principle. |
| **Voice feedback on focus save** | The island is silent by default; higgsfield cannot generate speech (TTS-only). Audio = `play(HUDSound.focusSaved)` if user opts in; otherwise visual confirmation only. |
| **Ambient video in closed slot** | Decorative video belongs in the idle board backdrop, not the pill. Closed island must stay instantly readable. |

---

## Architectural Decisions

### Decision 1: Focus Card is Session-Independent

**Why:** A user might be interrupted mid-Claude-session but need to jump to a Codex tab to grab something. The resume context is about *work state*, not *tool state*.

**Implementation:** `FocusCard.jumpTarget` is optional; if nil, tapping "Jump" selects the session that created it; if set (e.g., to a Codex thread), jumps there instead.

### Decision 2: Idle Board, Not Closed Pill

**Why:** Focus/Resume context is *not* an interrupt — it's a convenience after you *chose* to take a break. Showing it on the closed pill would make the island noisy and would compete with actual waiting agents.

**Implementation:** Resume card shows only in the idle board; dismissed via swipe/⎋; can be accessed later via shelf or a persistent "Resume" item.

### Decision 3: Shelf Pinning ≠ Favorites

**Why:** Pinned items are ephemeral and task-scoped ("I need this three times today"). The shelf is not a tagging system.

**Implementation:** Pinned items sort to the top and auto-unpin after 24h if unused; can manually unpin anytime.

### Decision 4: Health Signals Opt-In

**Why:** Proactive health alerts (Low Power Mode, thermals) are valuable for developers who care, but opt-in prevents alert fatigue for users who don't.

**Implementation:** Gated behind `DisplaySettings.showsHealthIndicators` (off by default); only critical states show without opt-in (e.g., "Disk full").

---

## Testing Strategy

### Phase 1 Tests

```swift
@Test("FocusCard.init(session:snippet) sets all fields")
func testFocusCardInitialization() throws {
    let session = AgentSession(id: "test", title: "Claude", ...)
    let card = FocusCard(from: session, snippet: "func resume() { ... }")
    #expect(card.title == "Claude")
    #expect(card.snippet.count <= 60)
}

@Test("Resume card dismissed by swipe re-appears after 7 days if re-created")
func testResumCardExpiry() async throws {
    // Harness: set focusCard.savedAt = 8 days ago
    // Resume card should not render
}
```

### Phase 2 Tests

```swift
@Test("Screen share monitor detects active capture stream")
func testScreenShareDetection() async throws {
    // Mock ScreenCaptureKit.contentFilters
    // Assert isCapturingSuspect toggles correctly
}

@Test("Pinned shelf item floats to top and expires after 24h")
func testShelfPinning() throws { ... }
```

### Phase 3 Tests

```swift
@Test("Time zone display syncs with CalendarLocation array")
func testTimeZoneDisplay() throws {
    let locations = [
        CalendarLocation(city: "San Francisco", timezone: .current),
        CalendarLocation(city: "London", timezone: TimeZone(abbreviation: "GMT")!),
    ]
    // Assert each renders correctly in idle board
}

@Test("Health signal only shows when critical or opted-in")
func testHealthSignalGating() throws { ... }
```

---

## Risk & Mitigation

| Risk | Mitigation |
|---|---|
| **Focus Card persistence corruption** | Store as JSON + checksum; invalid files silently reset to nil. No crash path. |
| **Interruption during save** | Save gesture is non-blocking (detached Task); UI confirmation is instant. |
| **Time zone DST edge case** | Use `TimeZone(abbreviation:)` from `Foundation` + test both March and November boundaries. |
| **Screen share false positive** | Whitelist legitimate capture (demo/recording tools); gate behind user settings. |

---

## Commit & PR Strategy

Phase 1 should land in 3 PRs:

1. `feat(focus-card): Add FocusCard model + ledger (OpenIslandCore)`
2. `feat(focus-card): Persist to disk; add SessionState.focusCard`
3. `feat(focus-card): UI gesture + idle board resume card`

Each PR is self-contained; CI green before merge.

---

## References

- **Current Architecture**: `docs/island-modules.md` (timer, calendar, shelf, HUD, now-playing, clipboard, ambient)
- **Closed Slot Design**: `Sources/OpenIslandCore/IslandClosedSlot.swift` + `IslandClosedArbiter.resolve()`
- **Session State**: `Sources/OpenIslandCore/SessionState.swift`
- **Settings**: `Sources/OpenIslandApp/SettingsStore.swift` (appearance, display, behaviour, HUD)

---

## Next Steps (After Audit)

1. **Week 1**: Assign Phase 1 tasks. Review `FocusCard` model + ledger design with team.
2. **Week 2**: Complete Phase 1 PRs; gather feedback on idle board resume card placement.
3. **Week 3–4**: Phase 2 (desktop guard + shelf pinning) in parallel with Phase 1 close-out.
4. **Week 5+**: Phase 3 (time zones + health) based on user research and feedback.

---

**Audit completed by:** Claude Agent  
**Branch:** `feat/manus-focus-card`  
**Approved for phased implementation:** 2026-09-20
