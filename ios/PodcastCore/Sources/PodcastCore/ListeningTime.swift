import Foundation

/// Accumulates real listening time for one play session.
///
/// Each periodic tick reports how much wall-clock time passed while playing and how far the
/// playhead moved. Wall time is what the listener actually spent (speed-adjusted: an hour at 2×
/// counts 30 min); media time is how much of the episode was covered. Seeks / skips are ignored:
/// a tick whose media delta is negative or far beyond `wall × maxRate` counts wall time only.
public struct ListeningSessionAccumulator: Sendable {
    public var maxRate: Double
    /// Ticks longer than this (app suspended, debugger…) are dropped.
    public var maxTickSeconds: Double

    public private(set) var wallSeconds: Double = 0
    public private(set) var mediaSeconds: Double = 0

    public init(maxRate: Double = 4, maxTickSeconds: Double = 5) {
        self.maxRate = maxRate
        self.maxTickSeconds = maxTickSeconds
    }

    public mutating func tick(wallDelta: Double, mediaDelta: Double, isPlaying: Bool) {
        guard isPlaying, wallDelta.isFinite, mediaDelta.isFinite,
              wallDelta > 0, wallDelta <= maxTickSeconds else { return }
        wallSeconds += wallDelta
        if mediaDelta > 0, mediaDelta <= wallDelta * maxRate + 0.5 {
            mediaSeconds += mediaDelta
        }
    }

    /// Returns and clears the accumulated totals (to persist them).
    public mutating func drain() -> (wall: Double, media: Double) {
        defer { wallSeconds = 0; mediaSeconds = 0 }
        return (wallSeconds, mediaSeconds)
    }
}

/// Picks the Statistics time for one episode.
public enum ListeningTimeRule {
    /// Recorded listened wall time when available, else the legacy wall-clock estimate
    /// (episode duration when played, saved position when in progress).
    public static func seconds(recordedWall: Double?, isPlayed: Bool, durationSeconds: Double, positionSeconds: Double) -> Double {
        if let recordedWall, recordedWall.isFinite, recordedWall > 0 { return recordedWall }
        if isPlayed { return durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 0 }
        return positionSeconds > 1 ? positionSeconds : 0
    }

    /// Seconds saved by listening faster than 1× (media covered minus wall time spent).
    public static func timeSaved(recordedWall: Double?, recordedMedia: Double?) -> Double {
        guard let w = recordedWall, let m = recordedMedia, w > 0, m > w else { return 0 }
        return m - w
    }
}
