import Foundation

/// Android `FeedPreferences.feedSkipIntro` / `feedSkipEnding` rules, shared by the global default
/// and the per-podcast override. Pure so it can be tested on Linux.
public enum SkipIntroOutro {
    /// Largest accepted value (one hour). Android takes any non-negative number; we cap typos.
    public static let maximumSeconds = 3600

    /// `nil` stays `nil` (use global). Negative or above the cap is rejected (`nil`).
    public static func normalized(_ seconds: Int?) -> Int? {
        guard let seconds, (0...maximumSeconds).contains(seconds) else { return nil }
        return seconds
    }

    /// Per-podcast override wins (an override of 0 turns skipping off for that podcast); else global.
    public static func resolved(feed: Int?, global: Int) -> Int {
        max(0, feed ?? global)
    }

    /// Whether a fresh-start seek to `intro` makes sense. Unknown duration (`<= 0`) allows it;
    /// a known duration rejects seeks at/after the end or into the skipped ending.
    public static func introSeekFits(intro: Double, outro: Double, duration: Double) -> Bool {
        guard intro > 0 else { return false }
        guard duration.isFinite, duration > 0 else { return true }
        if intro >= duration { return false }
        if outro > 0, outro < duration, duration - intro <= outro { return false }
        return true
    }

    /// Android `PlaybackService` skip-ending check: duration known and longer than the ending,
    /// playback past the first second, remaining time within the ending → skip to the next episode.
    public static func shouldSkipEnding(outro: Double, position: Double, duration: Double) -> Bool {
        guard outro > 0, duration.isFinite, duration > 0, outro < duration else { return false }
        guard position.isFinite, position > 1 else { return false }
        return duration - position <= outro
    }
}
