import Foundation

/// Android `EpisodeItemViewHolder` time label in episode lists:
/// - started, not played (position > 0 and < duration): with `prefShowTimeLeft`
///   ("Show remaining time") the right-hand label is `-remaining`, otherwise the duration;
/// - not started / played: the duration;
/// - `TimeSpeedConverter`: with `prefPlaybackTimeRespectsSpeed` every shown time is divided by
///   the episode's playback speed (iOS: per-podcast override ?? default speed, ≥ 0.5).
public enum EpisodeListTimeCaption {
    public struct Value: Equatable, Sendable {
        public var seconds: Double
        public var isRemaining: Bool
    }

    /// iOS keeps sub-second noise out of "started" (same as Resume / the progress bar).
    public static let startedThresholdSeconds: Double = 1

    public static func value(
        durationSeconds: Double?,
        positionSeconds: Double,
        isPlayed: Bool,
        showRemaining: Bool,
        respectsSpeed: Bool,
        speed: Float?
    ) -> Value? {
        guard let duration = durationSeconds, duration.isFinite, duration > 0 else { return nil }
        let factor: Double = respectsSpeed ? max(0.5, Double(speed ?? 1)) : 1
        let position = positionSeconds.isFinite ? max(0, positionSeconds) : 0
        let inProgress = !isPlayed && position > startedThresholdSeconds && position < duration
        if showRemaining, inProgress {
            return Value(seconds: (duration - position) / factor, isRemaining: true)
        }
        return Value(seconds: duration / factor, isRemaining: false)
    }

    /// `m:ss` / `h:mm:ss`, remaining prefixed with a minus sign (Android "-").
    public static func format(_ value: Value) -> String {
        let total = Int(value.seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return value.isRemaining ? "\u{2212}" + body : body
    }
}
