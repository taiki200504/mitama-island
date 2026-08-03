import Foundation

/// Tells the VS Code forks apart.
///
/// Every fork reports `TERM_PROGRAM=vscode`, so that variable alone cannot say
/// whether a session is running in VS Code, Cursor, Windsurf or Trae. The git
/// askpass helpers each fork installs do carry their own bundle path, which is
/// the one signal that survives across versions — `CURSOR_TRACE_ID` used to work
/// but current Cursor builds no longer set it.
public enum VSCodeForkIdentity {
    private static let askpassVariables = [
        "VSCODE_GIT_ASKPASS_NODE",
        "VSCODE_GIT_ASKPASS_MAIN",
    ]

    private static let bundleNames: [(needle: String, displayName: String)] = [
        ("cursor.app", "Cursor"),
        ("windsurf.app", "Windsurf"),
        ("trae cn.app", "Trae"),
        ("trae.app", "Trae"),
        ("visual studio code - insiders.app", "VS Code Insiders"),
        ("code - insiders.app", "VS Code Insiders"),
    ]

    /// The fork's display name, or `nil` when nothing in the environment names one.
    public static func displayName(from environment: [String: String]) -> String? {
        for variable in askpassVariables {
            guard let path = environment[variable]?.lowercased() else { continue }
            for candidate in bundleNames where path.contains(candidate.needle) {
                return candidate.displayName
            }
        }
        return nil
    }
}
