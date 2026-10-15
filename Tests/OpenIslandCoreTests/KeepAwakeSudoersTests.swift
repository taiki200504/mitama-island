import Testing
@testable import OpenIslandCore

struct KeepAwakeSudoersTests {
    @Test func rejectsInvalidUsernames() {
        for name in ["", "a b", "a\nroot", "a:b", "a,b", "a\\b", "a\"b", "$(id)", "三島", "é"] {
            #expect(KeepAwakeSudoers.contents(username: name) == nil)
        }
    }

    @Test func grantsOnlyExactPmsetCommands() {
        for name in ["taiki", "User_01.test-name", "123", "-user"] {
            #expect(KeepAwakeSudoers.contents(username: name) ==
                "\"\(name)\" ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n")
        }
    }
}
