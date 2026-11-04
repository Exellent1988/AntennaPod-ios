import Foundation

/// Shared **Play random** eligibility + pick for Feed / Favorites / Downloads / Queue /
/// History / Inbox / Archived / All Episodes.
///
/// Each view keeps its own catalog source (full queue, soft-capped All Episodes,
/// completed downloads only, non-archived feed episodes, …). This type only encodes:
/// - playable-media rules (`DownloadService.localURL` and/or streamable http(s))
/// - prefer-unplayed selection when any eligible unplayed remain
///
/// Behavior matches the prior per-view copies — **no product change**. Wi‑Fi stream
/// gate and resume rules still apply inside `PlaybackService.play`.
enum EpisodePlayRandom {
    /// Downloads requires a local file; other surfaces accept local **or** streamable http(s).
    enum MediaRequirement {
        /// Local file via `DownloadService.localURL` (completed download or local-folder
        /// `file://`) **or** streamable http(s) `downloadUrl` — Feed / Favorites / Queue /
        /// History / Inbox / Archived / All Episodes.
        case localOrStreamable
        /// Local file only (`DownloadService.localURL`) — Downloads Play random.
        case localFileOnly
    }

    /// Playable-media predicate matching prior per-view `episodeHasPlayableMedia` /
    /// Downloads local-file filter.
    static func playable(
        _ episode: PodcastEpisode,
        localURL: (PodcastEpisode) -> URL?,
        requirement: MediaRequirement = .localOrStreamable
    ) -> Bool {
        if localURL(episode) != nil { return true }
        guard requirement == .localOrStreamable else { return false }
        guard let raw = episode.downloadUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = EpisodeMediaURL.url(from: raw) else { return false }
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// Filter `episodes` with `playable`. Catalog membership is the caller's job.
    static func eligible(
        from episodes: [PodcastEpisode],
        localURL: (PodcastEpisode) -> URL?,
        requirement: MediaRequirement = .localOrStreamable
    ) -> [PodcastEpisode] {
        episodes.filter { playable($0, localURL: localURL, requirement: requirement) }
    }

    /// Prefer-unplayed candidate pool (same selection set `pick` draws from).
    /// Useful for `.disabled(candidates.isEmpty)` without drawing twice.
    static func candidates(
        from eligible: [PodcastEpisode],
        preferUnplayed: Bool = true,
        isPlayed: (String) -> Bool
    ) -> [PodcastEpisode] {
        guard preferUnplayed else { return eligible }
        let unplayed = eligible.filter { !isPlayed($0.id) }
        return unplayed.isEmpty ? eligible : unplayed
    }

    /// Uniform pick among `from`, preferring unplayed when `preferUnplayed` and any
    /// unplayed remain; otherwise any eligible. Empty → nil.
    static func pick(
        from episodes: [PodcastEpisode],
        preferUnplayed: Bool = true,
        isPlayed: (String) -> Bool
    ) -> PodcastEpisode? {
        candidates(from: episodes, preferUnplayed: preferUnplayed, isPlayed: isPlayed)
            .randomElement()
    }
}
