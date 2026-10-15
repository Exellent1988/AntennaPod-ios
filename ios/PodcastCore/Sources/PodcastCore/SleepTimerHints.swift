import Foundation

/// Android `SleepTimerDialog.refreshUiState` / `confirmAlwaysSleepTimerDialog` rules as pure
/// functions: which hint the sheet shows, which options are visible, and when Auto-enable with
/// an episode timer needs the "Disable continuous playback" confirmation.
public enum SleepTimerHints {
    /// Android `SLEEP_DURATION_DAILY_HOURS_CUTOFF`: a window longer than this is "most of the day".
    public static let mostOfDayCutoffHours = 12

    public enum Hint: Equatable, Sendable {
        /// Episode timer while continuous playback is off: always stops at the end of the episode.
        case episodesWithoutContinuousPlayback
        /// Episode timer longer than the queue: only `remaining` episodes left.
        case episodesExceedQueue(remaining: Int)
        /// Clock timer longer than the current episode while continuous playback is off.
        case timerExceedsEpisode(minutesLeft: Int)
    }

    /// - Parameters:
    ///   - continuousPlayback: Android `isFollowQueue` (any mode other than Off).
    ///   - queueRemaining: episodes queued after the current one; `nil` when unknown or not
    ///     advancing through the queue (no hint then, like Android before the count loads).
    ///   - episodeRemainingSeconds: time left in the current episode; `nil` when unknown.
    public static func hint(kind: SleepTimerKind, continuousPlayback: Bool, selectedEpisodes: Int,
                            selectedMinutes: Int?, queueRemaining: Int?,
                            episodeRemainingSeconds: Double?) -> Hint? {
        switch kind {
        case .episodes:
            if !continuousPlayback { return .episodesWithoutContinuousPlayback }
            if let queueRemaining, selectedEpisodes > queueRemaining {
                return .episodesExceedQueue(remaining: max(0, queueRemaining))
            }
            return nil
        case .clock:
            guard !continuousPlayback, let minutes = selectedMinutes,
                  let left = episodeRemainingSeconds, left.isFinite else { return nil }
            let leftSeconds = max(0, left)
            guard Double(minutes) * 60 > leftSeconds else { return nil }
            return .timerExceedsEpisode(minutesLeft: Int(leftSeconds / 60))
        }
    }

    /// Android disables starting an episode timer (and hides Auto-enable, Shake, Vibrate) when
    /// continuous playback is off.
    public static func canStart(kind: SleepTimerKind, continuousPlayback: Bool) -> Bool {
        kind == .clock || continuousPlayback
    }

    public static func showsOptions(kind: SleepTimerKind, continuousPlayback: Bool) -> Bool {
        canStart(kind: kind, continuousPlayback: continuousPlayback)
    }

    /// Android hides Shake to reset for the episode timer (it only applies to the clock timer).
    public static func showsShakeToReset(kind: SleepTimerKind) -> Bool { kind == .clock }

    /// Android `isSleepTimerConfiguredForMostOfTheDay`.
    public static func isMostOfDay(fromHour: Int, toHour: Int) -> Bool {
        SleepTimerLogic.autoEnableDurationHours(fromHour: fromHour, toHour: toHour) > mostOfDayCutoffHours
    }

    /// Android asks to disable continuous playback instead when Auto-enable is turned on (or the
    /// hours change) with an episode timer covering most of the day.
    public static func needsAlwaysEpisodeConfirmation(autoEnable: Bool, kind: SleepTimerKind,
                                                      fromHour: Int, toHour: Int) -> Bool {
        autoEnable && kind == .episodes && isMostOfDay(fromHour: fromHour, toHour: toHour)
    }

    /// Android `DBReader.getRemainingQueueSize`: queued episodes after the current one (all of
    /// them when the current episode is not queued).
    public static func remainingQueueSize(queueIds: [String], currentId: String?) -> Int {
        guard let currentId, let index = queueIds.firstIndex(of: currentId) else { return queueIds.count }
        return queueIds.count - index - 1
    }
}
