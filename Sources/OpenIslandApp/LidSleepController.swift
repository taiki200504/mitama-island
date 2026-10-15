import Foundation
import OpenIslandCore

/// Serializes privileged changes. The durable marker survives crashes and denied restoration.
@MainActor
final class LidSleepController {
    private let defaults: UserDefaults
    private let marker = "keepAwake.changedDisablesleep"
    private var desired = false
    private var task: Task<Void, Never>?
    var onFailure: (() -> Void)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func recover() async -> Bool {
        guard defaults.bool(forKey: marker) else { return true }
        if await Self.sleepDisabled() == false {
            defaults.removeObject(forKey: marker)
        } else {
            await restore()
        }
        return !defaults.bool(forKey: marker)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != desired else { return }
        desired = enabled
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            repeat {
                let target = desired
                if target {
                    // Record BEFORE the command: a crash after pmset must still recover.
                    defaults.set(true, forKey: marker)
                    defaults.synchronize()
                    if !(await Self.change(disabled: true)) { onFailure?() }
                } else {
                    await restore()
                }
                if target == desired { break }
            } while true
            task = nil
        }
    }

    func shutdown() async -> Bool {
        desired = false
        if let pending = task {
            await pending.value
        } else {
            await restore()
        }
        return !defaults.bool(forKey: marker)
    }

    private func restore() async {
        guard defaults.bool(forKey: marker) else { return }
        if await Self.sleepDisabled() == false {
            defaults.removeObject(forKey: marker)
            return
        }
        if await Self.change(disabled: false), await Self.sleepDisabled() == false {
            defaults.removeObject(forKey: marker)
        } else {
            onFailure?()
        }
    }

    private nonisolated static let sudoersPath = "/etc/sudoers.d/mitama-island-pmset"

    func preparePermission() async {
        guard !FileManager.default.fileExists(atPath: Self.sudoersPath),
              let contents = KeepAwakeSudoers.contents(username: NSUserName()) else { return }
        _ = await Task.detached {
            // Create and validate the staging file as root, never in a user-writable directory.
            let command = "set -eu; /bin/mkdir -p /etc/sudoers.d; "
                + "stage=$(/usr/bin/mktemp /etc/sudoers.d/mitama-island-pmset.XXXXXXXX); "
                + "trap '/bin/rm -f \"$stage\" \"$stage.ready\"' EXIT; "
                + "printf '%s' " + Self.shellQuote(contents) + " > \"$stage\"; "
                + "/usr/sbin/visudo -cf \"$stage\"; "
                + "/usr/bin/install -o root -g wheel -m 0440 \"$stage\" \"$stage.ready\"; "
                + "/bin/mv -f \"$stage.ready\" " + Self.sudoersPath
            return Self.administratorCommand(command)
        }.value
    }

    func removePermission() async -> Bool {
        // Restore before revoking the unattended restoration path.
        guard await shutdown() else { return false }
        return await Task.detached {
            Self.administratorCommand("/bin/rm -f " + Self.sudoersPath)
        }.value
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private nonisolated static func administratorCommand(_ command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    private nonisolated static func change(disabled: Bool) async -> Bool {
        await Task.detached {
            let value = disabled ? "1" : "0"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 { return true }
            } catch { /* Fall back to interactive authorization. */ }
            return administratorCommand("/usr/bin/pmset -a disablesleep " + value)
        }.value
    }

    private nonisolated static func sleepDisabled() async -> Bool? {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8),
                  output.contains("Currently in use:") else { return nil }
            guard let regex = try? NSRegularExpression(pattern: "(?im)^\\s*(?:SleepDisabled|disablesleep)\\s+([01])\\b"),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                  let range = Range(match.range(at: 1), in: output) else { return false } // pmset omits SleepDisabled when it is off.
            return output[range] == "1"
        }.value
    }
}
