import Foundation

/// Android `prefFavoriteKeepsEpisode` ("Keep favorite episodes", default **on**, global only;
/// Settings → Downloads → Auto delete). It only gates the delete-after-playing path
/// (`PlaybackService.onPostPlayback`: `shouldAutoDelete && (!favorite || !shouldFavoriteKeepEpisode())`).
/// Episode cleanup (`APCleanupAlgorithm`, `APQueueCleanupAlgorithm`, `ExceptFavoriteCleanupAlgorithm`)
/// skips favorites unconditionally, independent of this setting.
public enum FavoriteKeepPolicy {
    public static let defaultFavoriteKeepsEpisode = true

    /// Delete the download after playing?
    public static func deleteAfterPlaying(autoDeleteAllowed: Bool, isFavorite: Bool, favoriteKeepsEpisode: Bool) -> Bool {
        autoDeleteAllowed && (!isFavorite || !favoriteKeepsEpisode)
    }

    /// Cleanup / cache-limit candidates never include favorites (Android, regardless of the setting).
    public static func cleanupMayDelete(isFavorite: Bool) -> Bool { !isFavorite }
}
