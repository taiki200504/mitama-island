import Foundation
import OpenIslandCore

/// Where the videos behind `AmbientBackdropPreference.video` live on disk.
///
/// Never bundled: Apple's own Aerial clips are not redistributable, and
/// licensing a substitute is a cost this feature doesn't need to carry. The
/// owner drops their own `.mov`/`.mp4`/`.m4v` in; an empty folder just means
/// the gradient keeps showing.
enum AmbientVideoFolder {
    /// `Application Support/MitamaIsland/Ambient`, unless
    /// `DisplaySettings.ambientVideoFolderPath` points somewhere else.
    static func directory(customPath: String) -> URL {
        guard !customPath.isEmpty else { return defaultDirectory }
        return URL(fileURLWithPath: customPath, isDirectory: true)
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MitamaIsland/Ambient", isDirectory: true)
    }

    /// Creates the folder on first use — a user turning the setting to
    /// "video" should find somewhere to drop a file, not an error.
    static func availableVideos(customPath: String) -> [URL] {
        let directory = directory(customPath: customPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return AmbientVideoLibrary.videos(in: contents)
    }
}
