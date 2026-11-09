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

/// Full player hero sizing (Android: large square cover above the controls).
public enum PlayerHeroLayout {
    /// Vertical space the portrait controls need below the cover (header, seek bar, main row, bottom bar).
    public static let portraitControlsHeight: Double = 380
    public static let minimumCover: Double = 120
    /// Gap under the bottom bar (speed · sleep · audio · visualizer) so it never touches the edge.
    public static let bottomBarInset: Double = 24
    public static let maximumCover: Double = 520

    /// Landscape when wider than tall.
    public static func isLandscape(width: Double, height: Double) -> Bool { width > height }

    /// Cover edge length for the available content size (safe area already excluded).
    public static func coverSide(width: Double, height: Double) -> Double {
        guard width > 0, height > 0 else { return minimumCover }
        let side: Double
        if isLandscape(width: width, height: height) {
            side = min(height - 32, width * 0.42)
        } else {
            side = min(width - 48, height - portraitControlsHeight)
        }
        return min(max(side, minimumCover), maximumCover)
    }
}

/// Android-style seek bar: thin track, small round thumb. Track runs from thumb centre at 0 to
/// thumb centre at 1, so chapter ticks and the thumb share one coordinate system.
public enum SeekBarGeometry {
    public static let thumbDiameter: Double = 14
    public static let trackHeight: Double = 4
    /// Touch target height (thumb is small, the hit area is not).
    public static let hitHeight: Double = 44

    public static func clampedFraction(_ f: Double) -> Double {
        guard f.isFinite else { return 0 }
        return min(max(f, 0), 1)
    }

    /// Usable track length between the thumb centres at 0 and 1.
    public static func trackLength(width: Double) -> Double {
        max(0, width - thumbDiameter)
    }

    /// x of the thumb centre / a chapter tick for a fraction.
    public static func x(forFraction f: Double, width: Double) -> Double {
        thumbDiameter / 2 + trackLength(width: width) * clampedFraction(f)
    }

    /// Fraction for a touch location.
    public static func fraction(forX x: Double, width: Double) -> Double {
        let len = trackLength(width: width)
        guard len > 0 else { return 0 }
        return clampedFraction((x - thumbDiameter / 2) / len)
    }
}
