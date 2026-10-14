import Foundation

/// Seek-bar chapter dividers (Android `ChapterSeekBar`): fractions 0…1 of the duration where a
/// chapter starts. The first chapter at 0, starts at/after the end, unknown durations and
/// near-duplicates (closer than `minimumGap` of the bar) are dropped.
public enum ChapterMarks {
    public static func fractions(starts: [Double], duration: Double, minimumGap: Double = 0.005) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        var out: [Double] = []
        for start in starts.sorted() where start.isFinite && start > 0 && start < duration {
            let f = start / duration
            if let last = out.last, f - last < minimumGap { continue }
            out.append(f)
        }
        return out
    }
}

/// Order of the per-podcast settings screen, matching Android `FeedSettingsFragment` for the
/// playback and download groups (speed, volume adaptation, skip silence, intro/outro,
/// auto-download + filter, auto-delete, keep updated). iOS-only rows follow.
public enum FeedSettingsRow: String, CaseIterable, Sendable {
    case playbackSpeed
    case volumeAdaptation
    case skipSilence
    case skipIntro
    case skipOutro
    case autoDownload
    case episodeFilter
    case autoDelete
    case keepUpdated
    case newEpisodesAction
    case notifications
    case episodeSort
    case authentication
    case tags

    /// Section the row lives in.
    public var group: FeedSettingsGroup {
        switch self {
        case .playbackSpeed, .volumeAdaptation, .skipSilence, .skipIntro, .skipOutro: return .playback
        case .autoDownload, .episodeFilter, .autoDelete: return .downloads
        case .keepUpdated, .newEpisodesAction, .notifications: return .updates
        case .episodeSort, .authentication, .tags: return .other
        }
    }

    /// Whether the row only matters while auto-download is effectively on (Android greys it out).
    public var dependsOnAutoDownload: Bool { self == .episodeFilter }
}

public enum FeedSettingsGroup: String, CaseIterable, Sendable {
    case playback, downloads, updates, other

    /// Groups in on-screen order (first appearance of their rows).
    public static var ordered: [FeedSettingsGroup] {
        var seen: [FeedSettingsGroup] = []
        for row in FeedSettingsRow.allCases where !seen.contains(row.group) { seen.append(row.group) }
        return seen
    }
}
