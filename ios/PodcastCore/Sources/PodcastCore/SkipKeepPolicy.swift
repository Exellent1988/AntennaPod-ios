import Foundation

/// Android `prefSkipKeepsEpisode` ("Keep skipped episodes", default **on**, global only).
/// `PlaybackService.onPostPlayback`: a *skipped* episode is marked played and removed from the
/// queue only when Keep is off — or when it was almost finished anyway (Smart mark as played).
/// Natural end and Skip ending (`autoSkipped`) always mark played. Progress is saved either way,
/// and gpodder gets a `play` action with the real position (`enqueueEpisodePlayed(media, ended || almostEnded)`).
public enum SkipKeepPolicy {
    public static let defaultKeepSkippedEpisodes = true

    /// Whether a manual skip finishes the episode (mark played + leave the queue).
    public static func skipMarksPlayed(keepSkipped: Bool, almostEnded: Bool) -> Bool {
        !keepSkipped || almostEnded
    }

    /// Per-podcast override (`nil` = use global).
    public static func resolved(feed: Bool?, global: Bool) -> Bool {
        feed ?? global
    }
}
