import Foundation

/// Android `PlaybackPreferences.currentlyPlayingTemporaryPlaybackSpeed`: a speed picked in the
/// player belongs to the loaded episode only. It is persisted the moment it changes (a crash or a
/// kill never runs a shutdown hook), and it is kept apart from both the global default
/// (`settings.defaultPlaybackSpeed`) and the per-podcast override (`FeedSettings.playbackSpeed`).
public struct SessionPlaybackSpeed: Equatable, Sendable {
    public var episodeId: String
    public var speed: Float

    public init(episodeId: String, speed: Float) {
        self.episodeId = episodeId
        self.speed = speed
    }

    /// UserDefaults keys (watched by the settings leak check: prefix `playback.`).
    public static let episodeIdKey = "playback.sessionSpeedEpisodeId"
    public static let speedKey = "playback.sessionSpeed"

    /// Effective start speed for `episodeId`: the saved session speed when it was picked for this
    /// same episode, else feed override ?? global default.
    public static func resolve(
        episodeId: String,
        saved: SessionPlaybackSpeed?,
        feedOverride: Float?,
        global: Float
    ) -> Float {
        if let saved, saved.episodeId == episodeId, saved.speed.isFinite, saved.speed > 0 {
            return saved.speed
        }
        return feedOverride ?? global
    }

    public static func load(from defaults: UserDefaults = .standard) -> SessionPlaybackSpeed? {
        guard let id = defaults.string(forKey: episodeIdKey),
              defaults.object(forKey: speedKey) != nil else { return nil }
        return SessionPlaybackSpeed(episodeId: id, speed: defaults.float(forKey: speedKey))
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(episodeId, forKey: Self.episodeIdKey)
        defaults.set(speed, forKey: Self.speedKey)
    }

    public static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: episodeIdKey)
        defaults.removeObject(forKey: speedKey)
    }
}
