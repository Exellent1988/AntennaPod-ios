import Foundation

/// Shared remaining-time math for list / Home info bars (and Subscriptions unplayed map).
/// Callers pass the **exact episode set** they already filtered (visible / preview /
/// soft-cap / search hits / etc.) — this type never chooses scopes.
///
/// Per episode when duration is known: wall-clock `max(0, duration − position)`. Unplayed
/// with known duration contributes full duration (position 0). **Played** (not the live
/// current episode) → 0 remaining (regardless of stored position; mark-played clears
/// position only when Settings reset-on-mark-played is on). **Unknown duration skipped**
/// (`unknownCount`; UI prefixes `~` when any skipped). Currently playing prefers live
/// `PlaybackService` position/duration when the caller supplies them.
///
/// Default is **wall-clock**. When callers pass `effectivePlaybackSpeed`, each episode’s
/// remaining is divided by `max(0.5, speed)` (feed override ?? global default — estimate;
/// session rate / volume boost are not applied here for list/Home totals).
///
/// Distinct from `WidgetRemainingTime` (single Continue snapshot labels). Chapter list
/// current remaining starts as `ChapterIndexing.remainingSeconds` (wall-clock end − position);
/// display may speed-adjust via `playerChromeRemainingSeconds` when Settings respects speed.
/// Player chrome −remaining (mini/full) and chapter-list current remaining use the same
/// helper — live session rate preferred over feed/default (clamped 0.5…3.0).
enum EpisodeRemainingTime {
    /// Aggregate over one caller-chosen episode list.
    struct Summary: Equatable {
        var episodeCount: Int
        var remainingSeconds: Double
        var knownCount: Int
        var unknownCount: Int
    }

    // MARK: - Duration / position

    /// Prefer live player duration when this episode is current; else feed `itunes:duration` /
    /// media; else saved playback duration. Never invents a length.
    static func knownDurationSeconds(
        for episode: PodcastEpisode,
        currentEpisodeId: String?,
        liveDurationSeconds: Double,
        savedDurationSeconds: Double
    ) -> Double? {
        if currentEpisodeId == episode.id {
            let live = liveDurationSeconds
            if live.isFinite, live > 0 { return live }
        }
        if episode.hasKnownDuration {
            return episode.durationSeconds
        }
        if savedDurationSeconds.isFinite, savedDurationSeconds > 0 {
            return savedDurationSeconds
        }
        return nil
    }

    /// Feed duration when known; else saved playback duration. No live player (e.g. queue
    /// duration sort on `PodcastStore` without `PlaybackService`).
    static func knownDurationSeconds(
        for episode: PodcastEpisode,
        savedDurationSeconds: Double
    ) -> Double? {
        knownDurationSeconds(
            for: episode,
            currentEpisodeId: nil,
            liveDurationSeconds: 0,
            savedDurationSeconds: savedDurationSeconds
        )
    }

    /// Live player position when current; else saved progress (`0` when unplayed / cleared).
    static func positionSeconds(
        episodeId: String,
        currentEpisodeId: String?,
        livePositionSeconds: Double,
        savedPositionSeconds: Double
    ) -> Double {
        if currentEpisodeId == episodeId {
            let live = livePositionSeconds
            return live.isFinite ? max(0, live) : 0
        }
        return max(0, savedPositionSeconds)
    }

    // MARK: - Sum

    /// Sum remaining over `episodes` (caller-owned set). Same edge cases as former per-view loops.
    /// Minimum divisor when speed-adjusting (matches custom playback speed lower bound).
    static let minimumPlaybackSpeedDivisor: Float = 0.5
    /// Maximum divisor when speed-adjusting player/chapter chrome (matches Custom… upper bound).
    static let maximumPlaybackSpeedDivisor: Float = 3.0

    /// Wall-clock remaining divided by effective speed (clamped to ≥ `minimumPlaybackSpeedDivisor`).
    static func speedAdjustedRemainingSeconds(wallClockSeconds: Double, playbackSpeed: Float) -> Double {
        let divisor = max(Double(minimumPlaybackSpeedDivisor), Double(playbackSpeed))
        guard divisor > 0, wallClockSeconds.isFinite else { return max(0, wallClockSeconds) }
        return max(0, wallClockSeconds) / divisor
    }

    /// Divisor for mini/full −remaining and chapter-list current remaining when Settings →
    /// Remaining time respects speed is on. Prefer live `PlaybackService.rate`; if non-finite /
    /// ≤ 0, use `fallbackSpeed` (feed override ?? default). Clamped to 0.5…3.0.
    static func playerChromeSpeedDivisor(sessionRate: Float, fallbackSpeed: Float) -> Float {
        let preferred: Float
        if sessionRate.isFinite, sessionRate > 0 {
            preferred = sessionRate
        } else if fallbackSpeed.isFinite, fallbackSpeed > 0 {
            preferred = fallbackSpeed
        } else {
            preferred = 1.0
        }
        return min(
            maximumPlaybackSpeedDivisor,
            max(minimumPlaybackSpeedDivisor, preferred)
        )
    }

    /// Mini/full scrubber −remaining **and** chapter-list current remaining (duration-from-now).
    /// When `respectsSpeed` is false, wall-clock. When true, divide by live session rate
    /// (fallback feed/default), clamped 0.5…3.0. Chapter **duration** labels stay wall-clock.
    /// Lock Screen / Now Playing / Widget / Watch are not wired through this helper.
    static func playerChromeRemainingSeconds(
        wallClockSeconds: Double,
        respectsSpeed: Bool,
        sessionRate: Float,
        fallbackSpeed: Float
    ) -> Double {
        guard respectsSpeed else { return max(0, wallClockSeconds) }
        return speedAdjustedRemainingSeconds(
            wallClockSeconds: wallClockSeconds,
            playbackSpeed: playerChromeSpeedDivisor(
                sessionRate: sessionRate,
                fallbackSpeed: fallbackSpeed
            )
        )
    }

    static func summarize(
        episodes: some Sequence<PodcastEpisode>,
        currentEpisodeId: String?,
        liveDurationSeconds: Double,
        livePositionSeconds: Double,
        isPlayed: (String) -> Bool,
        savedDurationSeconds: (String) -> Double,
        savedPositionSeconds: (String) -> Double,
        /// When non-nil, divide each episode’s wall-clock remaining by that speed (estimate).
        /// Nil keeps today’s wall-clock default. Played → 0 is unchanged (skipped before divide).
        effectivePlaybackSpeed: ((PodcastEpisode) -> Float)? = nil
    ) -> Summary {
        var remaining = 0.0
        var known = 0
        var unknown = 0
        var count = 0
        for episode in episodes {
            count += 1
            guard let duration = knownDurationSeconds(
                for: episode,
                currentEpisodeId: currentEpisodeId,
                liveDurationSeconds: liveDurationSeconds,
                savedDurationSeconds: savedDurationSeconds(episode.id)
            ) else {
                unknown += 1
                continue
            }
            known += 1
            // Mark-played clears position; do not count full duration as still left
            // (unless this is the live current episode — use live position instead).
            if isPlayed(episode.id), currentEpisodeId != episode.id {
                continue
            }
            let position = positionSeconds(
                episodeId: episode.id,
                currentEpisodeId: currentEpisodeId,
                livePositionSeconds: livePositionSeconds,
                savedPositionSeconds: savedPositionSeconds(episode.id)
            )
            let wallClock = max(0, duration - position)
            if let speedFor = effectivePlaybackSpeed {
                remaining += speedAdjustedRemainingSeconds(
                    wallClockSeconds: wallClock,
                    playbackSpeed: speedFor(episode)
                )
            } else {
                remaining += wallClock
            }
        }
        return Summary(
            episodeCount: count,
            remainingSeconds: remaining,
            knownCount: known,
            unknownCount: unknown
        )
    }

    // MARK: - Labels (shared EN/DE String Catalog keys — unchanged wording)

    /// AntennaPod-like info bar: `N episodes • Hh Mm left` (prefix `~` when unknowns).
    /// `nil` when `episodeCount == 0`. Count-only when all durations unknown (no invented time).
    static func episodesInfoBarLabel(for summary: Summary) -> String? {
        guard summary.episodeCount > 0 else { return nil }
        let episodesWord: String
        if summary.episodeCount == 1 {
            episodesWord = String(localized: "1 episode")
        } else {
            episodesWord = String(localized: "\(summary.episodeCount) episodes")
        }
        guard summary.knownCount > 0 else {
            return episodesWord
        }
        return String(localized: "\(episodesWord) • \(timePart(for: summary)) left")
    }

    /// Subscriptions info bar: `N unplayed • Hh Mm left` (prefix `~` when unknowns).
    /// `nil` when `episodeCount == 0`. Count-only when all durations unknown.
    static func unplayedInfoBarLabel(for summary: Summary) -> String? {
        guard summary.episodeCount > 0 else { return nil }
        let unplayedWord: String
        if summary.episodeCount == 1 {
            unplayedWord = String(localized: "1 unplayed")
        } else {
            unplayedWord = String(localized: "\(summary.episodeCount) unplayed")
        }
        guard summary.knownCount > 0 else {
            return unplayedWord
        }
        return String(localized: "\(unplayedWord) • \(timePart(for: summary)) left")
    }

    /// Compact per-feed / row fragment: `"Hh Mm left"` or `"~… left"`.
    /// `nil` when no known durations (no invented time).
    static func timeLeftLabel(remainingSeconds: Double, knownCount: Int, unknownCount: Int) -> String? {
        guard knownCount > 0 else { return nil }
        let formatted = StatisticsView.formatDuration(remainingSeconds)
        let timePart: String
        if unknownCount > 0 {
            timePart = String(localized: "~\(formatted)")
        } else {
            timePart = formatted
        }
        return String(localized: "\(timePart) left")
    }

    private static func timePart(for summary: Summary) -> String {
        let formatted = StatisticsView.formatDuration(summary.remainingSeconds)
        if summary.unknownCount > 0 {
            return String(localized: "~\(formatted)")
        }
        return formatted
    }
}
