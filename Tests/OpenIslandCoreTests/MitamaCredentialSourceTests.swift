import Foundation
import Testing
@testable import OpenIslandCore

/// The key grants access to the notification queue, so where it is read from
/// matters as much as whether it loads.
struct MitamaCredentialSourceTests {
    private func writeEnvFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mitama-\(UUID().uuidString).env")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test
    func readsAPlaintextFileWhenTheKeychainHasNothing() throws {
        let url = try writeEnvFile("""
        SUPABASE_URL=https://example.supabase.co
        SUPABASE_KEY=secret-value
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = MitamaEnvironment.loadWithSource(from: url)

        #expect(loaded?.source == .envFile)
        #expect(loaded?.environment.url.absoluteString == "https://example.supabase.co")
    }

    @Test
    func reportsNothingWhenNeitherSourceHasCredentials() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).env")

        #expect(MitamaEnvironment.loadWithSource(from: missing) == nil)
    }

    /// A file holding only half the pair cannot produce a working client.
    @Test
    func aHalfFilledFileIsRefused() throws {
        let url = try writeEnvFile("SUPABASE_URL=https://example.supabase.co")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MitamaEnvironment.loadWithSource(from: url) == nil)
    }

    @Test
    func theKeychainAccountNamesMatchWhatAddkeyWrites() {
        #expect(MitamaKeychain.urlAccount == "MITAMA_SUPABASE_URL")
        #expect(MitamaKeychain.keyAccount == "MITAMA_SUPABASE_KEY")
    }

    /// Absent keychain entries must not throw or block; they simply yield nil so
    /// the file fallback runs.
    @Test
    func anAbsentKeychainEntryIsQuiet() {
        #expect(MitamaKeychain.value(for: "MITAMA_DEFINITELY_NOT_PRESENT_\(UUID().uuidString)") == nil)
    }
}
