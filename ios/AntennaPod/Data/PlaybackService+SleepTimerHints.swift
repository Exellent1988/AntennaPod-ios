import Foundation
import PodcastCore

/// Android `SleepTimerDialog.refreshUiState` inputs from the live player, settings and queue.
extension PlaybackService {
    var sleepTimerContinuousPlayback: Bool {
        (settings?.continuousPlaybackMode ?? .queue) != .off
    }

    /// Queued episodes after the current one; `nil` unless continuous playback follows the queue.
    var sleepTimerQueueRemaining: Int? {
        guard settings?.continuousPlaybackMode ?? .queue == .queue, let store else { return nil }
        return SleepTimerHints.remainingQueueSize(queueIds: store.queue.map(\.id), currentId: currentEpisode?.id)
    }

    func sleepTimerHint(kind: SleepTimerKind, episodes: Int, minutes: Int?) -> SleepTimerHints.Hint? {
        let left: Double? = (currentEpisode != nil && durationSeconds > 0) ? durationSeconds - positionSeconds : nil
        return SleepTimerHints.hint(kind: kind, continuousPlayback: sleepTimerContinuousPlayback,
                                    selectedEpisodes: episodes, selectedMinutes: minutes,
                                    queueRemaining: sleepTimerQueueRemaining, episodeRemainingSeconds: left)
    }

    static func sleepTimerHintText(_ hint: SleepTimerHints.Hint) -> String {
        switch hint {
        case .episodesWithoutContinuousPlayback:
            return String(localized: "Continuous playback is disabled in the settings. Always stopping at the end of the episode.")
        case .episodesExceedQueue(let n):
            return n == 1 ? String(localized: "There is only 1 episode left in your queue")
                : String(format: String(localized: "There are only %lld episodes left in your queue"), n)
        case .timerExceedsEpisode(let m):
            return m == 1 ? String(localized: "Continuous playback is disabled and the current episode has only 1 minute left")
                : String(format: String(localized: "Continuous playback is disabled and the current episode has only %lld minutes left"), m)
        }
    }
}
