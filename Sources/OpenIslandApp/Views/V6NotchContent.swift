import SwiftUI
import OpenIslandCore

/// Per-cell state for the closed-island agents grid. Drives tile rendering:
/// running = full color, idle = dim, waiting = opacity pulse.
enum AgentGridCellState: Equatable {
    case running
    case idle
    case waiting
}

/// One cell in the closed-island agents grid. `.session` carries the agent
/// tool's brand color and its current state. `.overflow` is a single trailing
/// cell shown when there are more sessions than the grid can display.
enum AgentGridCell: Equatable {
    case session(color: Color, state: AgentGridCellState)
    case overflow(Int)
}

/// Concrete payload for the closed island's right slot. The `AppModel`
/// computes one of these from live session state according to the user's
/// `islandRightSlot` preference; the view side is agnostic to which
/// setting produced it.
enum IslandRightSlotContent: Equatable {
    case count(Int)              // "×N" badge
    case agents([AgentGridCell]) // balanced grid, one tile per session
}

// MARK: - Right-slot renderers

struct V6RightSlotView: View {
    let content: IslandRightSlotContent

    var body: some View {
        switch content {
        case .count(let n):
            Text("×\(n)")
                .font(.islandMono(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(V6Palette.paper.opacity(0.72))
        case .agents(let cells):
            AgentsGridBody(cells: cells)
        }
    }

    /// Intrinsic width used by the fluid-layout math. Values are slightly
    /// padded beyond the raw text measurement so the pill always reserves
    /// enough room for the `.fixedSize()` content to render on one line,
    /// without HStack compression forcing a wrap.
    static func intrinsicWidth(of content: IslandRightSlotContent) -> CGFloat {
        switch content {
        case .count(let n):
            let digits = Double(max(1, String(n).count))
            // "×" + digits at 11pt mono ≈ 7.2pt/char.
            return CGFloat(14.4 + max(0.0, digits - 1.0) * 7.2)
        case .agents(let cells):
            let n = cells.count
            guard n > 0 else { return 0 }
            let rows = balancedRows(n)
            let maxRow = rows.max() ?? 0
            let geom = cellGeometry(rowCount: rows.count)
            return CGFloat(maxRow) * geom.cell + CGFloat(max(0, maxRow - 1)) * geom.gap
        }
    }

    // MARK: Balanced layout algorithm
    //
    // For each n from 1 to 9, we hand-tune the per-row cell counts so the
    // matrix reads as a deliberate shape instead of a wrap-at-4-columns grid.
    // For n >= 10 the AppModel caps the list at 7 sessions + 1 overflow cell,
    // which lays out as [4,4] — so balancedRows(8) is what actually renders
    // for all high-count cases in production.
    static func balancedRows(_ n: Int) -> [Int] {
        switch n {
        case ..<1: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        default: return [4, 4]
        }
    }

    /// Cell size shrinks when the matrix has 3 rows so total height still
    /// fits inside the pill's internal vertical budget (~20pt).
    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        if rowCount >= 3 { return (cell: 6, gap: 1.5, radius: 1.0) }
        return (cell: 8, gap: 2, radius: 1.5)
    }

    static func splitIntoRows(_ cells: [AgentGridCell], rowSizes: [Int]) -> [[AgentGridCell]] {
        var out: [[AgentGridCell]] = []
        var idx = 0
        for size in rowSizes {
            let end = min(idx + size, cells.count)
            out.append(Array(cells[idx..<end]))
            idx = end
            if idx >= cells.count { break }
        }
        return out
    }
}

// MARK: - Agents grid body

/// V1a Dense Grid renderer. 2D matrix of 8×8 rounded squares (6×6 when 3 rows),
/// each row horizontally centered around the widest row. Running = full color,
/// idle = 22% alpha, waiting = opacity 0.35 ↔ 1 breathing pulse.
private struct AgentsGridBody: View {
    let cells: [AgentGridCell]

    var body: some View {
        let rowSizes = V6RightSlotView.balancedRows(cells.count)
        let geom = V6RightSlotView.cellGeometry(rowCount: rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        AgentsGridTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct AgentsGridTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                AgentsGridWaitingTile(color: color, size: size, radius: radius)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.islandMono(size: max(5, size * 0.55), weight: .bold))
                    .foregroundStyle(V6Palette.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct AgentsGridWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Center label renderer

struct V6CenterLabelView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.islandMono(size: 11.5, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V6Palette.paper)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        CGFloat(Double(text.count) * 7.3 + 10)
    }
}

// MARK: - Closed-pill layouts

/// The canonical v6 closed-island pill rendered inside a fixed-height frame.
/// Pure view — takes all parameters explicitly so it can be reused for the
/// live settings preview and the real island.
struct V6ClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?          // suppressed automatically in MacBook layout
    var rightSlot: IslandRightSlotContent?
    /// The arbiter's one body + one trailing accessory. Non-nil body widens
    /// the pill the same way the old peek band did; the island is otherwise
    /// the same size it always was.
    var content: IslandClosedContent?
    /// A temporary message that overrides the body for a few seconds — the
    /// timer finished, the track changed. Empty text keeps the pop's old
    /// scale-only behaviour: nothing else about the pill changes.
    var sneakPeek: IslandSneakPeek?
    var layout: V6ClosedLayout
    var height: CGFloat = 32

    /// MacBook mode only — width of the physical notch cutout to wrap.
    var physicalNotchWidth: CGFloat = 0

    /// External mode only — minimum pill width (locked). Defaults to the
    /// width that fits just the glyph.
    var minWidth: CGFloat = 70

    /// Bumped by `AppModel` when Reduce Motion is toggled, so the band
    /// animation below re-evaluates immediately instead of waiting for
    /// `label`/`rightSlot`/`mode`/`peek` to change on their own.
    var motionRevision: Int = 0

    /// How far past the notch's own bleed the pill may widen before the
    /// accessory has to give way. Matches `OverlayPanelController.closedPillSideBleed`
    /// on both sides.
    private static let accessoryDropBleed: CGFloat = 33

    private var showsSneakPeek: Bool {
        guard let sneakPeek else { return false }
        return !sneakPeek.text.isEmpty
    }

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // Horizontal edge padding is identical left/right — canonical v6 pill
    // has r = h/2 semicircular bottoms, so edge inset = r keeps content
    // clear of the curve.
    private var pad: CGFloat { height / 2 }

    // Minimum breathing room between the center label (or glyph, when no
    // label) and the right-slot content so they never touch at small widths.
    private static let innerGap: CGFloat = 6

    // MARK: External (fluid)

    private var externalBody: some View {
        let glyphW: CGFloat = 24
        let hasBody = content?.body != nil
        let peekW = showsSneakPeek
            ? (sneakPeek?.intrinsicWidth() ?? 0)
            : (hasBody ? (content?.intrinsicWidth(layout: layout) ?? 0) : 0)
        let showsPeekArea = showsSneakPeek || hasBody
        // The peek area replaces the session-name label while something is
        // showing. Both would fit here, but reading a session title next to
        // "who is waiting and for how long" buries the second in the first.
        let showsLabel = label != nil && !showsPeekArea
        let labelW = showsLabel ? V6CenterLabelView.intrinsicWidth(of: label ?? "") : 0
        let rightW = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0
        let accessory = content?.resolvedAccessory()
        let accessoryW = accessory.map { IslandClosedAccessoryView.intrinsicWidth(of: $0) } ?? 0

        let labelBlock = (showsLabel ? 6 + labelW : 0)
        let peekBlock = (showsPeekArea ? Self.innerGap + peekW : 0)
        let accessoryBlock = (accessory == nil ? 0 : Self.innerGap + accessoryW)
        let rightBlock = (rightSlot == nil ? 0 : Self.innerGap + rightW)
        let intrinsic = pad * 2 + glyphW + labelBlock + peekBlock + accessoryBlock + rightBlock
        let width = max(minWidth, intrinsic)

        return ZStack {
            V6ClosedPillShape()
                .fill(V6Palette.ink)

            HStack(spacing: 0) {
                UnifiedBars(mode: mode, size: 24)
                    .frame(width: glyphW, height: 24)

                if showsSneakPeek, let sneakPeek {
                    SAOSneakPeekView(peek: sneakPeek)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if hasBody, let content {
                    SAOPeekGaugeView(content: content)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                if showsLabel, let label {
                    V6CenterLabelView(text: label)
                        .padding(.leading, 6)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                if let accessory {
                    IslandClosedAccessoryView(accessory: accessory)
                        .padding(.trailing, Self.innerGap)
                }

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(
            IslandMotion.resolved(IslandMotion.bandChange),
            value: AnyHashable([
                AnyHashable(label ?? ""),
                AnyHashable(rightSlot.map(RightSlotKey.init) ?? .none),
                AnyHashable(mode),
                AnyHashable(content),
                AnyHashable(sneakPeek),
                AnyHashable(motionRevision),
            ])
        )
    }

    // MARK: MacBook (outer width locked)

    private var macbookBody: some View {
        // The two sides stay the same width so the physical cutout keeps
        // sitting in the middle of the pill. Widening only the side that needs
        // the room would slide the hardware notch off-centre, which reads as a
        // rendering bug rather than as new information.
        let maxContentWidth = physicalNotchWidth + Self.accessoryDropBleed * 2
        let hasBody = content?.body != nil
        let peekW = showsSneakPeek
            ? (sneakPeek?.intrinsicWidth() ?? 0)
            : (hasBody ? (content?.intrinsicWidth(layout: layout, maxWidth: maxContentWidth) ?? 0) : 0)
        let showsPeekArea = showsSneakPeek || hasBody
        let accessory = showsSneakPeek ? nil : content?.resolvedAccessory(maxWidth: maxContentWidth)
        let leftContent = 24 + (showsPeekArea ? Self.innerGap + peekW : 0)
        let rightContent = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0
        let halfReserve = max(44, pad + max(leftContent, rightContent) + Self.innerGap)
        let outer = halfReserve + physicalNotchWidth + halfReserve

        return ZStack {
            V6ClosedPillShape()
                .fill(V6Palette.ink)

            HStack(spacing: 0) {
                UnifiedBars(mode: mode, size: 24)
                    .frame(width: 24, height: 24)

                if showsSneakPeek, let sneakPeek {
                    SAOSneakPeekView(peek: sneakPeek)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if hasBody, let content {
                    SAOPeekGaugeView(content: content)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                if let accessory {
                    IslandClosedAccessoryView(accessory: accessory)
                        .padding(.trailing, Self.innerGap)
                }

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: outer, height: height)
        .animation(
            IslandThemes.current.animationProfile.open,
            value: AnyHashable([AnyHashable(content), AnyHashable(sneakPeek), AnyHashable(mode)])
        )
    }
}

// MARK: - Peek gauge

/// The closed island's answer to "is anything waiting on me".
///
/// Everything it needs is already decided by `IslandClosedArbiter`; this only
/// draws it. Fixed-English throughout — the same choice the old peek band
/// made for the agent name — because this is a HUD readout in the
/// crystal-HUD grammar's own display face, and Rajdhani has no glyphs to
/// localize it into.
struct SAOPeekGaugeView: View {
    let content: IslandClosedContent

    @State private var urgentPulse = false

    var body: some View {
        if let islandBody = content.body {
            let level = SAOPeekGauge.gaugeLevel(for: islandBody)
            let urgent = SAOPeekGauge.isUrgent(islandBody)
            let others = SAOPeekGauge.othersCount(for: islandBody)

            HStack(spacing: 5) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(SAOGrammar.Palette.statusYellow)

                Text(SAOPeekGauge.label(for: islandBody))
                    .saoCaps(size: 11)
                    .foregroundStyle(V6Palette.paper.opacity(0.92))

                ZStack(alignment: .leading) {
                    SAOGaugeShape(fraction: 1, isTrack: true)
                        .fill(V6Palette.paper.opacity(0.14))
                    SAOGaugeShape(fraction: level.fraction)
                        .fill(level.tint)
                        .opacity(urgent ? (urgentPulse ? 1 : 0.4) : 1)
                        .onAppear {
                            guard urgent else { return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                urgentPulse = true
                            }
                        }
                }
                .frame(width: 44, height: 6)

                Text(SAOPeekGauge.elapsedText(for: islandBody))
                    .font(.islandMono(size: 11))
                    .foregroundStyle(V6Palette.paper.opacity(0.62))

                if others > 0 {
                    SAOPeekTailStrip(count: others, isWaiting: SAOPeekGauge.tailIsWaiting(for: islandBody))
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The trailing "+N" count, redrawn as a strip of blocks instead of a number:
/// still-waiting things breathe statusYellow, everything else (calendar
/// entries further ahead) sits dim and still.
private struct SAOPeekTailStrip: View {
    let count: Int
    let isWaiting: Bool
    @State private var breathe = false

    var body: some View {
        SAOBlockStrip(
            cells: count,
            cellSize: CGSize(width: 8, height: 8),
            gap: 2,
            color: isWaiting ? SAOGrammar.Palette.statusYellow : V6Palette.paper.opacity(0.22)
        )
        .opacity(isWaiting ? (breathe ? 1 : 0.55) : 1)
        .onAppear {
            guard isWaiting else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

/// A temporary closed-island message — the timer finished, the track
/// changed — drawn in place of the peek gauge for as long as it lives.
struct SAOSneakPeekView: View {
    let peek: IslandSneakPeek

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: peek.icon)
                .font(.islandMono(size: 10, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.92))

            Text(peek.text)
                .font(.islandMono(size: 11))
                .foregroundStyle(V6Palette.paper.opacity(0.92))

            if let gauge = peek.gauge {
                ZStack(alignment: .leading) {
                    SAOGaugeShape(fraction: 1, isTrack: true)
                        .fill(V6Palette.paper.opacity(0.14))
                    SAOGaugeShape(fraction: gauge)
                        .fill(SAOGrammar.Palette.hpLimeEnd)
                }
                .frame(width: 44, height: 6)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Trailing accessory

/// The one thing the closed island shows besides the body: a timer, what's
/// playing, that the camera is watching, or that the shelf has something on
/// it. Never more than one at a time — `IslandClosedArbiter` already decided
/// which.
struct IslandClosedAccessoryView: View {
    let accessory: IslandClosedAccessory

    var body: some View {
        Group {
            switch accessory {
            case .timer(let remainingMinutes, _):
                Text("\(remainingMinutes)m")
                    .font(.islandMono(size: 11, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.85))
            case .nowPlaying(let isPlaying):
                NowPlayingVisualiser(isPlaying: isPlaying)
            case .cameraWatching:
                // The same glyph the peek band used to draw for this — macOS
                // lights its own camera indicator for as long as the device
                // runs, and this is the island's only way to say why.
                Image(systemName: "hand.raised.fill")
                    .font(.islandMono(size: 9, weight: .semibold))
                    .foregroundStyle(IslandThemes.current.statusTints.waitingForAnswer.opacity(0.92))
            case .shelf(let count):
                HStack(spacing: 3) {
                    Image(systemName: "tray.full")
                        .font(.islandMono(size: 9, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.7))
                    Text("\(count)")
                        .font(.islandMono(size: 11))
                        .foregroundStyle(V6Palette.paper.opacity(0.7))
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Reserved width for `accessory` alone — no leading gap; the caller adds
    /// that when it decides the accessory fits.
    static func intrinsicWidth(of accessory: IslandClosedAccessory) -> CGFloat {
        let charWidth: CGFloat = 7.2
        switch accessory {
        case .timer(let remainingMinutes, _):
            return CGFloat("\(remainingMinutes)m".count) * charWidth
        case .nowPlaying:
            return 14
        case .cameraWatching:
            return 11
        case .shelf(let count):
            return 11 + CGFloat("\(count)".count) * charWidth
        }
    }
}

/// A 3-bar pseudo visualiser: bars only move while something is actually
/// playing, so a paused track reads as at-rest rather than as broken.
private struct NowPlayingVisualiser: View {
    let isPlaying: Bool
    @State private var animate = false

    private static let barHeights: [CGFloat] = [4, 8, 5]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.85))
                    .frame(width: 2, height: isPlaying && animate ? height : height * 0.4)
            }
        }
        .frame(width: 14, height: 8, alignment: .bottom)
        .onAppear {
            guard isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Closed content sizing

@MainActor
extension IslandClosedContent {
    private static let peekCharWidth: CGFloat = 7.2   // Departure Mono at 11pt
    private static let peekDotWidth: CGFloat = 6 + 5
    private static let peekGaugeWidth: CGFloat = 44
    private static let peekInnerGap: CGFloat = 5
    private static let peekTailCell: CGFloat = 8
    private static let peekTailGap: CGFloat = 2

    private func tailStripWidth(cells: Int) -> CGFloat {
        guard cells > 0 else { return 0 }
        return CGFloat(cells) * Self.peekTailCell + CGFloat(max(0, cells - 1)) * Self.peekTailGap
    }

    fileprivate func bodyWidth() -> CGFloat {
        guard let body else { return 0 }
        let label = SAOPeekGauge.label(for: body)
        let elapsed = SAOPeekGauge.elapsedText(for: body)
        let others = SAOPeekGauge.othersCount(for: body)

        var width = Self.peekDotWidth
        width += CGFloat(label.count) * Self.peekCharWidth + Self.peekInnerGap
        width += Self.peekGaugeWidth + Self.peekInnerGap
        width += CGFloat(elapsed.count) * Self.peekCharWidth
        if others > 0 {
            width += Self.peekInnerGap + tailStripWidth(cells: others)
        }
        return width
    }

    /// The accessory to actually render at `maxWidth` — nil when showing it
    /// would push the pill past its width budget. The body — whatever is
    /// actually waiting on you — is never the one that gives way; the
    /// accessory is dropped first.
    func resolvedAccessory(maxWidth: CGFloat = .infinity) -> IslandClosedAccessory? {
        guard let accessory else { return nil }
        let full = bodyWidth() + Self.peekInnerGap + IslandClosedAccessoryView.intrinsicWidth(of: accessory)
        return full <= maxWidth ? accessory : nil
    }

    /// Width this content asks the pill to reserve at `maxWidth`, matching
    /// `resolvedAccessory(maxWidth:)`'s decision about whether the accessory
    /// survives.
    func intrinsicWidth(layout: V6ClosedLayout, maxWidth: CGFloat = .infinity) -> CGFloat {
        let body = bodyWidth()
        guard let accessory = resolvedAccessory(maxWidth: maxWidth) else { return body }
        return body + Self.peekInnerGap + IslandClosedAccessoryView.intrinsicWidth(of: accessory)
    }
}

extension IslandSneakPeek {
    /// Width the pill must reserve to show this sneak peek's icon, text, and
    /// optional gauge. Only meaningful when `text` isn't empty — the empty-text
    /// "shelf pop" draws nothing extra and asks for none.
    func intrinsicWidth() -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let charWidth: CGFloat = 7.2
        let icon: CGFloat = 10 + 5
        let textWidth = CGFloat(text.count) * charWidth
        let gaugeWidth: CGFloat = gauge != nil ? 44 + 5 : 0
        return icon + textWidth + gaugeWidth
    }
}

enum V6ClosedLayout: Equatable {
    case external
    case macbook
}

private enum RightSlotKey: Hashable {
    case count(Int)
    case agents(Int)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):    self = .count(n)
        case .agents(let cs):  self = .agents(cs.count)
        }
    }
}

// MARK: - Settings-tab live preview

/// Fixed-width pill that mimics the real island inside the settings-tab
/// preview stage. Parameters match what the tab exposes.
struct IslandPreviewPill: View {
    let mode: UnifiedBars.Mode
    let label: String?
    let rightSlot: IslandRightSlotContent?
    let layout: V6ClosedLayout
    let physicalNotchWidth: CGFloat
    let now: Date

    var body: some View {
        V6ClosedPill(
            mode: mode,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            physicalNotchWidth: physicalNotchWidth
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
