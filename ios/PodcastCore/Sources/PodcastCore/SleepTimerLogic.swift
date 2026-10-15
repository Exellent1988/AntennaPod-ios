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
