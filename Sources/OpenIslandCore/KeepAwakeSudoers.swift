/// The only passwordless commands granted for closed-lid keep awake.
public enum KeepAwakeSudoers {
    public static func contents(username: String) -> String? {
        guard !username.isEmpty, username.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 46 || $0 == 95 || $0 == 45
        }) else { return nil }
        // Quote the sudoers user token so numeric names cannot mean a uid.
        return "\"\(username)\" ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }
}
