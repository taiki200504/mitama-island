import Foundation
import Security

/// Reads mitama's Supabase credentials out of the login keychain.
///
/// The alternative — and what this replaces as the preferred source — is a
/// plaintext `.env` sitting in the repository tree. A key that grants access to
/// the notification queue should not be readable by anything that can read the
/// user's home directory.
///
/// Values are written by `addkey`, which stores them as generic passwords under
/// `service = <NAME>`, `account = $USER`.
public enum MitamaKeychain {
    public static let urlAccount = "MITAMA_SUPABASE_URL"
    public static let keyAccount = "MITAMA_SUPABASE_KEY"

    /// Nil when either value is absent, so a half-configured keychain falls back
    /// rather than producing a client that cannot authenticate.
    public static func environment() -> MitamaEnvironment? {
        guard let urlText = value(for: urlAccount),
              let url = URL(string: urlText),
              let apiKey = value(for: keyAccount) else {
            return nil
        }
        return MitamaEnvironment(url: url, apiKey: apiKey)
    }

    /// Reads without ever putting a panel on screen.
    ///
    /// The items were written by `addkey`, so this app is not on their access
    /// list, and every rebuild changes the binary — the "Mitama Island wants to
    /// use a keychain item" panel therefore came back after every install,
    /// asking for the login password to read a notification feed. A background
    /// nicety must not interrogate the user.
    ///
    /// `kSecUseAuthenticationUI` was the first attempt and does nothing here: it
    /// governs the biometric/passcode prompt for items guarded by an access
    /// *control*, not the password panel an access *list* mismatch produces.
    /// The switch for that one is process-wide and lives on the old
    /// `SecKeychain` API, which is deprecated but has no replacement for this.
    ///
    /// Refusing the panel turns the mismatch into a plain failure, and the
    /// caller falls back to the .env file. An app already on the list still
    /// reads without any UI, so nothing is lost by refusing to ask.
    public static func value(for service: String) -> String? {
        setUserInteraction(allowed: false)
        defer { setUserInteraction(allowed: true) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Process-wide, so it is turned back on the moment the read is done —
    /// anything else in the app that legitimately needs to ask still can.
    private static func setUserInteraction(allowed: Bool) {
        SecKeychainSetUserInteractionAllowed(allowed)
    }
}
