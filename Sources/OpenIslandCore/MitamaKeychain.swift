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

    public static func value(for service: String) -> String? {
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
}
