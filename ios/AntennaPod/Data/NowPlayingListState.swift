import Combine
import Foundation

/// What list screens (Home Weiterspielen, Inbox, Episodes, Queue, feed list, Downloads, History,
/// Subscriptions) observe about playback. Android parity: list rows bind the *stored*
/// `FeedMedia.position`, refreshed on pause / stop / episode change (PlaybackPositionEvent only
/// drives the mini player and the player screen).
@MainActor
final class NowPlayingListState: ObservableObject {
    let playback: PlaybackService
    weak var store: PodcastStore?
    private var cancellables: Set<AnyCancellable> = []

    init(playback: PlaybackService, store: PodcastStore?) {
        self.playback = playback
        self.store = store
        // Baseline: lists re-render on every PlaybackService change (incl. each 0.5 s tick).
        playback.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Called from the playback publishers (and tests) when the loaded episode or play state changes.
    func updateNowPlaying(episodeId: String?, isPlaying: Bool) {}

    /// Stored position of the loaded episode (what list rows / totals show).
    var storedPositionSeconds: Double {
        guard let id = playback.currentEpisode?.id else { return 0 }
        return store?.positionSeconds(for: id) ?? 0
    }

    /// Stored duration of the loaded episode, else the player's (set once per item).
    var storedDurationSeconds: Double {
        if let id = playback.currentEpisode?.id, let d = store?.playbackState(for: id).durationSeconds, d > 0 { return d }
        return playback.durationSeconds
    }
}
