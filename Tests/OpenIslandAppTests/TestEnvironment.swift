import Foundation

/// Where the tests are running. A handful of tests depend on the machine
/// (a live terminal process table, wall-clock timers that a busy CI runner
/// stalls for seconds); they run locally and are skipped on CI.
enum TestEnvironment {
    static let isCI: Bool = ProcessInfo.processInfo.environment["CI"] != nil
}
