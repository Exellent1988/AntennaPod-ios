import Foundation

/// Android AntennaPod sleep timer rules (`SleepTimerPreferences`, `ClockSleepTimer`,
/// `ShakeListener`, `PlaybackService.sleepTimerUpdate`) as pure functions.
public enum SleepTimerLogic {
    /// Android `SleepTimer.NOTIFICATION_THRESHOLD`: vibrate, start shake listening and fade here.
    public static let warningSeconds: Double = 10
    /// Android `ShakeListener`: total acceleration above 2.25 g counts as a shake.
    public static let shakeThresholdG: Double = 2.25
    /// Android auto-enable window defaults (22:00 to 06:00).
    public static let defaultAutoEnableFromHour = 22
    public static let defaultAutoEnableToHour = 6
    /// Android `SleepTimerDialog` extend buttons (minutes).
    public static let extendMinutes = [5, 10, 30]
    /// Android rewinds half the warning window after the timer pauses playback.
    public static var rewindAfterExpirySeconds: Double { warningSeconds / 2 }

    /// Android `SleepTimerPreferences.isInTimeRange`; `from == to` means the whole day
    /// (Android skips the hour check then). Hours outside 0…23 are wrapped.
    public static func isInAutoEnableWindow(fromHour: Int, toHour: Int, hour: Int) -> Bool {
        let from = wrap(fromHour), to = wrap(toHour), now = wrap(hour)
        if from == to { return true }
        if from < to { return from <= now && now < to }
        return now >= from || now < to   // overnight, e.g. 22 → 6
    }

    /// Android `autoEnableDuration` (hours covered by the window).
    public static func autoEnableDurationHours(fromHour: Int, toHour: Int) -> Int {
        let from = wrap(fromHour), to = wrap(toHour)
        return from >= to ? 24 - (from - to) : to - from
    }

    /// Auto-enable on playback start: setting on, no timer yet, and inside the window.
    public static func shouldAutoEnable(enabled: Bool, timerActive: Bool,
                                        fromHour: Int, toHour: Int, hour: Int) -> Bool {
        enabled && !timerActive && isInAutoEnableWindow(fromHour: fromHour, toHour: toHour, hour: hour)
    }

    /// Remaining clock time: running (`endDate`) wins over the paused remainder. Never negative.
    public static func remainingSeconds(endDate: Date?, pausedRemaining: Double?, now: Date) -> Double? {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        if let pausedRemaining { return max(0, pausedRemaining) }
        return nil
    }

    /// Inside the last `warningSeconds` (exclusive of 0, which is expiry).
    public static func isInWarningWindow(remaining: Double) -> Bool {
        remaining > 0 && remaining < warningSeconds
    }

    /// Android's fade multipliers per whole second left (index 0 = last second).
    public static let androidFadeSteps: [Float] = [0.1, 0.2, 0.3, 0.3, 0.3, 0.4, 0.4, 0.4, 0.6, 0.8]

    /// Volume factor for `remaining` seconds: 1 outside the warning window, then Android's
    /// step curve, interpolated between seconds so the pipeline gain ramps without steps.
    public static func fadeVolume(remaining: Double) -> Float {
        guard remaining.isFinite else { return 1 }
        if remaining >= warningSeconds { return 1 }
        if remaining <= 0 { return androidFadeSteps[0] }
        let index = Int(remaining)
        let low = androidFadeSteps[index]
        let high = index + 1 < androidFadeSteps.count ? androidFadeSteps[index + 1] : 1
        return low + (high - low) * Float(remaining - Double(index))
    }

    /// Android `ShakeListener`: acceleration in g on each axis (gravity included).
    public static func isShake(x: Double, y: Double, z: Double) -> Bool {
        (x * x + y * y + z * z).squareRoot() > shakeThresholdG
    }

    private static func wrap(_ hour: Int) -> Int { ((hour % 24) + 24) % 24 }
}

/// Android `EpisodeSleepTimer` (SleepTimerType.EPISODES): stop after N finished episodes.
/// An episode counts when it ends naturally, by Skip ending, or by a manual skip to the next
/// episode (Android `episodeFinishedPlayback` on end or skip); opening another episode does not.
public struct EpisodeSleepCounter: Equatable, Sendable {
    /// Sheet stepper range (Android takes any positive number; 1…20 covers real use).
    public static let range: ClosedRange<Int> = 1...20
    /// Android `SleepTimerDialog` extend buttons for the episode type: +1 / +2 / +3.
    public static let extendSteps = [1, 2, 3]

    public private(set) var initial: Int
    public private(set) var remaining: Int

    public init(episodes: Int) {
        let n = Self.clamp(episodes)
        initial = n
        remaining = n
    }

    /// Android `isEndingThisEpisode`: the current episode is the last one (fade / vibrate here).
    public var isOnLastEpisode: Bool { remaining == 1 }

    /// Records a finished episode. Returns `true` when playback may continue to the next one
    /// (Android `shouldContinueToNextEpisode`: episodes left > 0).
    @discardableResult
    public mutating func episodeFinished() -> Bool {
        remaining = max(0, remaining - 1)
        return remaining > 0
    }

    public mutating func extend(by episodes: Int) {
        guard episodes > 0 else { return }
        remaining = min(remaining + episodes, Self.range.upperBound * 2)
    }

    /// Shake to reset: back to the initial count.
    public mutating func reset() { remaining = initial }

    /// Time left on the last episode (for fade / warning); `nil` when not on the last episode
    /// or the duration is unknown.
    public func lastEpisodeRemainingSeconds(position: Double, duration: Double) -> Double? {
        guard isOnLastEpisode, duration.isFinite, duration > 0, position.isFinite else { return nil }
        return max(0, duration - position)
    }

    public static func clamp(_ episodes: Int) -> Int { min(max(episodes, range.lowerBound), range.upperBound) }
}

/// Android `SleepTimerType`: the sheet remembers which kind was used last.
public enum SleepTimerKind: String, Codable, CaseIterable, Sendable {
    case clock
    case episodes
}
