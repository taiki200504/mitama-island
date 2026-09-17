import Foundation

/// A level earned by finishing work: every session an agent completes is
/// experience, and the level rises on a gentle curve — 5 completions to reach
/// level 2, 10 more for level 3, 15 more for level 4, and so on.
///
/// Only a number to feel good about. Nothing is unlocked or withheld by it.
public enum IslandLevel {
    /// Completions per step of the curve: level `n` needs `step × n` more
    /// completions than level `n − 1` did.
    public static let step = 5

    /// Total completions needed to stand at `level` (level 1 needs none).
    public static func threshold(for level: Int) -> Int {
        let n = max(level, 1) - 1
        return step * n * (n + 1) / 2
    }

    /// The level these many completions have reached.
    public static func level(forCompletions completions: Int) -> Int {
        var level = 1
        while threshold(for: level + 1) <= completions {
            level += 1
        }
        return level
    }

    /// 0…1, how far into the current level towards the next.
    public static func progress(forCompletions completions: Int) -> Double {
        let level = level(forCompletions: max(completions, 0))
        let floor = threshold(for: level)
        let ceiling = threshold(for: level + 1)
        return Double(max(completions, 0) - floor) / Double(ceiling - floor)
    }

    /// The new level when going from `before` to `after` completions crosses
    /// into one, nil otherwise.
    public static func levelReached(from before: Int, to after: Int) -> Int? {
        let old = level(forCompletions: max(before, 0))
        let new = level(forCompletions: max(after, 0))
        return new > old ? new : nil
    }
}
