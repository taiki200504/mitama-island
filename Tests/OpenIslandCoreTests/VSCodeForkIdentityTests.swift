import Foundation
import Testing
@testable import OpenIslandCore

/// Every fork reports `TERM_PROGRAM=vscode`, so a session in Cursor was being
/// labelled "VS Code" and jumps went to the wrong editor.
struct VSCodeForkIdentityTests {
    private func askpass(_ appPath: String) -> [String: String] {
        ["VSCODE_GIT_ASKPASS_NODE": "\(appPath)/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"]
    }

    @Test
    func recognisesCursor() {
        #expect(VSCodeForkIdentity.displayName(from: askpass("/Applications/Cursor.app")) == "Cursor")
    }

    @Test
    func recognisesTheOtherForks() {
        #expect(VSCodeForkIdentity.displayName(from: askpass("/Applications/Windsurf.app")) == "Windsurf")
        #expect(VSCodeForkIdentity.displayName(from: askpass("/Applications/Trae.app")) == "Trae")
        #expect(
            VSCodeForkIdentity.displayName(from: askpass("/Applications/Visual Studio Code - Insiders.app"))
                == "VS Code Insiders"
        )
    }

    /// Plain VS Code has no fork name to report, so the caller keeps its default.
    @Test
    func plainVSCodeReportsNothing() {
        #expect(VSCodeForkIdentity.displayName(from: askpass("/Applications/Visual Studio Code.app")) == nil)
        #expect(VSCodeForkIdentity.displayName(from: [:]) == nil)
    }

    /// The main askpass script names the fork too, and only one of the two
    /// variables is guaranteed to be present.
    @Test
    func eitherAskpassVariableIsEnough() {
        let environment = [
            "VSCODE_GIT_ASKPASS_MAIN": "/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass-main.js"
        ]
        #expect(VSCodeForkIdentity.displayName(from: environment) == "Cursor")
    }

    /// `CURSOR_TRACE_ID` was the previous signal; current Cursor builds no
    /// longer set it, which is what broke the detection.
    @Test
    func doesNotDependOnCursorTraceID() {
        var environment = askpass("/Applications/Cursor.app")
        environment["CURSOR_TRACE_ID"] = nil
        #expect(VSCodeForkIdentity.displayName(from: environment) == "Cursor")
    }
}
