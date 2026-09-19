import Foundation

/// Detects if mitama Browser is actively driving a page by checking for established
/// TCP connections to the Chrome DevTools port (127.0.0.1:9222).
///
/// Automation is present when there is at least one non-browser client connected
/// to the DevTools port.
public enum BrowserAutomationProbe {
    /// Parses lsof output to detect established connections to the DevTools port
    /// (excluding the browser's own listen socket).
    ///
    /// - Parameters:
    ///   - lsofOutput: Raw output from `lsof -nP -iTCP@127.0.0.1:9222 -sTCP:ESTABLISHED`
    ///   - browserPID: The process ID of mitama Browser itself, which we exclude
    ///                 to avoid counting the browser's own listen socket
    /// - Returns: `true` if at least one external client is connected to DevTools
    public static func isDriven(lsofOutput: String, browserPID: pid_t) -> Bool {
        guard !lsofOutput.isEmpty else { return false }

        let lines = lsofOutput.split(separator: "\n", omittingEmptySubsequences: true)
        var foundEstablished = false

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            // lsof output format (simplified for our needs):
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // Example: mitama 1234 user 5u IPv4 0x123 0t0 TCP 127.0.0.1:9222 (ESTABLISHED)

            guard let pidString = parts[safe: 1],
                  let pid = pid_t(pidString),
                  pid != browserPID else {
                continue
            }

            // Connection is established to the DevTools port
            foundEstablished = true
            break
        }

        return foundEstablished
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
