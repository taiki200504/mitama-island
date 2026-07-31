import SwiftUI
import OpenIslandCore

/// A tiny bitmap mark drawn as square "pixels".
///
/// Session rows need to say *which agent* and *where it is running* in the
/// width of two characters. Glyphs beat SF Symbols here: at 10pt a symbol
/// turns to mush, while a hand-placed 5-row bitmap stays legible, and the
/// deliberate chunkiness reads as "terminal" rather than "productivity app".
///
/// Rows are strings so the art is editable in place — `#` is ink, anything
/// else is empty.
struct PixelGlyph: Equatable {
    let rows: [String]

    init(_ rows: [String]) {
        self.rows = rows
    }

    var height: Int { rows.count }
    var width: Int { rows.map(\.count).max() ?? 0 }

    /// Ink coordinates, top-left origin.
    var points: [(x: Int, y: Int)] {
        var result: [(x: Int, y: Int)] = []
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character == "#" {
                result.append((x, y))
            }
        }
        return result
    }
}

// MARK: - Agent marks

extension PixelGlyph {
    /// Every agent mark is 7×5 so a column of rows stays aligned.
    static let claudeCode = PixelGlyph([
        ".#####.",
        "##...##",
        "##.....",
        "##...##",
        ".#####.",
    ])

    static let codex = PixelGlyph([
        "##...##",
        ".##.##.",
        "..###..",
        ".##.##.",
        "##...##",
    ])

    static let gemini = PixelGlyph([
        "...#...",
        ".#.#.#.",
        "#..#..#",
        ".#.#.#.",
        "...#...",
    ])

    static let cursorAgent = PixelGlyph([
        "##.....",
        "###....",
        "####...",
        "##.##..",
        "#...##.",
    ])

    static let openCode = PixelGlyph([
        "###.###",
        "#.....#",
        "#.....#",
        "#.....#",
        "###.###",
    ])

    /// Fallback for the Claude Code forks (Kimi, Qwen, Factory, CodeBuddy,
    /// Qoder…). They behave identically, so they share one mark.
    static let genericAgent = PixelGlyph([
        ".#####.",
        "#.#.#.#",
        "#######",
        "#.....#",
        ".#.#.#.",
    ])

    static func agentMark(for tool: AgentTool) -> PixelGlyph {
        switch tool {
        case .claudeCode:
            return .claudeCode
        case .codex:
            return .codex
        case .geminiCLI:
            return .gemini
        case .cursor:
            return .cursorAgent
        case .openCode:
            return .openCode
        case .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI:
            return .genericAgent
        }
    }
}

// MARK: - Host marks

extension PixelGlyph {
    /// Host marks are 5×5 — narrower than the agent mark so the pair reads as
    /// "agent, running in host" rather than two peers.
    static let terminalHost = PixelGlyph([
        "#....",
        ".#...",
        "#....",
        ".....",
        ".####",
    ])

    static let editorHost = PixelGlyph([
        "#####",
        "#.#..",
        "#.#..",
        "#.#..",
        "#####",
    ])

    static let multiplexerHost = PixelGlyph([
        "#####",
        "#.#.#",
        "#####",
        "#.#.#",
        "#####",
    ])

    static let desktopAppHost = PixelGlyph([
        "#####",
        "#...#",
        "#...#",
        "#####",
        "..#..",
    ])

    static let unknownHost = PixelGlyph([
        ".....",
        "..#..",
        ".###.",
        "..#..",
        ".....",
    ])

    /// Maps the terminal/IDE name carried on a jump target to a mark.
    /// Matching is by lowercased substring because the same host arrives
    /// spelled several ways ("iTerm", "iTerm2", "iterm.app").
    static func hostMark(for terminalApp: String?) -> PixelGlyph {
        guard let name = terminalApp?.lowercased(), !name.isEmpty else {
            return .unknownHost
        }

        if name.contains("tmux") || name.contains("zellij") || name.contains("cmux") {
            return .multiplexerHost
        }
        if name.contains("code")
            || name.contains("cursor")
            || name.contains("windsurf")
            || name.contains("trae")
            || name.contains("zed")
            || name.contains("qoder")
            || name.contains("intellij")
            || name.contains("storm")
            || name.contains("pycharm")
            || name.contains("goland")
            || name.contains("clion")
            || name.contains("rider")
            || name.contains("rubymine")
            || name.contains("rustrover") {
            return .editorHost
        }
        if name.contains(".app") || name.contains("desktop") || name.contains("claude") {
            return .desktopAppHost
        }
        if name.contains("unknown") {
            return .unknownHost
        }

        return .terminalHost
    }
}

// MARK: - Rendering

/// Draws a ``PixelGlyph`` at a fixed pixel size with a soft bloom, so the mark
/// reads as emissive against the island's black rather than as a flat icon.
struct PixelGlyphView: View {
    let glyph: PixelGlyph
    var tint: Color
    var pixelSize: CGFloat = 2
    var glowRadius: CGFloat = 2.5

    private var size: CGSize {
        CGSize(
            width: CGFloat(glyph.width) * pixelSize,
            height: CGFloat(glyph.height) * pixelSize
        )
    }

    var body: some View {
        Canvas { context, _ in
            for point in glyph.points {
                let rect = CGRect(
                    x: CGFloat(point.x) * pixelSize,
                    y: CGFloat(point.y) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(tint))
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: tint.opacity(0.55), radius: glowRadius)
        .accessibilityHidden(true)
    }
}

/// The agent + host pair shown at the leading edge of a session row.
struct SessionGlyphPair: View {
    let tool: AgentTool
    let terminalApp: String?
    let tint: Color
    var pixelSize: CGFloat = 2

    var body: some View {
        HStack(spacing: pixelSize * 2) {
            PixelGlyphView(glyph: .agentMark(for: tool), tint: tint, pixelSize: pixelSize)
            PixelGlyphView(
                glyph: .hostMark(for: terminalApp),
                tint: tint.opacity(0.75),
                pixelSize: pixelSize,
                glowRadius: 1.8
            )
        }
    }
}
