import Foundation

/// Skip silence aggressiveness (global and per podcast). Android's ExoPlayer processor has one
/// fixed profile; these levels trade safety (keeping natural pauses) against time saved.
public enum SkipSilenceLevel: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case off
    case mild
    case medium
    case aggressive

    public var id: String { rawValue }

    /// Levels that actually skip (for the global level picker).
    public static let activeLevels: [SkipSilenceLevel] = [.mild, .medium, .aggressive]

    /// Below this RMS (dBFS) a block counts as silent.
    public var thresholdDB: Double {
        switch self {
        case .off, .medium: return -45
        case .mild: return -50
        case .aggressive: return -40
        }
    }

    /// Silence must last this long before speeding up (natural pauses shorter than this are kept).
    public var minimumSilence: Double {
        switch self {
        case .off, .medium: return 0.35
        case .mild: return 0.6
        case .aggressive: return 0.2
        }
    }

    /// Rate multiplier on top of the user's speed while skipping.
    public var speedup: Float {
        switch self {
        case .off: return 1
        case .mild: return 2
        case .medium: return 3
        case .aggressive: return 4
        }
    }

    /// Detector configured for this level (release 5 dB above threshold = hysteresis).
    public var detector: SilenceDetector {
        SilenceDetector(thresholdDB: thresholdDB, releaseDB: thresholdDB + 5, minimumSilence: minimumSilence)
    }

    /// Resolution order: per-feed level → per-feed on/off (on uses the global level) → global.
    /// `globalEnabled` is the existing master switch; `globalLevel` the global aggressiveness.
    public static func resolved(
        feedLevel: SkipSilenceLevel?, feedEnabled: Bool?,
        globalEnabled: Bool, globalLevel: SkipSilenceLevel
    ) -> SkipSilenceLevel {
        let activeGlobal = globalLevel == .off ? .medium : globalLevel
        if let feedLevel { return feedLevel }
        if let feedEnabled { return feedEnabled ? activeGlobal : .off }
        return globalEnabled ? activeGlobal : .off
    }
}

/// Smooth rate changes: a sequence of intermediate rates instead of one jump.
public enum RateRamp {
    /// Rates to apply, one per step, ending exactly at `to`. Each step changes by ≤ `maxStep`.
    public static func steps(from: Float, to: Float, maxStep: Float) -> [Float] {
        guard maxStep > 0, from.isFinite, to.isFinite else { return [to] }
        let delta = to - from
        let count = max(1, Int((abs(delta) / maxStep).rounded(.up)))
        return (1...count).map { i in i == count ? to : from + delta * Float(i) / Float(count) }
    }
}
