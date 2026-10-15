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
        // Only episode change and play / pause reach the lists, never the 0.5 s position tick.
        playback.$currentEpisode.map { $0?.id }
            .combineLatest(playback.$isPlaying)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] id, playing in
                // @Published fires before the value is stored: apply on the next turn.
                DispatchQueue.main.async { self?.updateNowPlaying(episodeId: id, isPlaying: playing) }
            }
            .store(in: &cancellables)
    }

    private var lastEpisodeId: String?
    private var lastIsPlaying = false

    /// Called from the playback publishers (and tests) when the loaded episode or play state changes.
    /// While an episode plays its periodic saves stay quiet; pause / stop / switch publishes them once.
    func updateNowPlaying(episodeId: String?, isPlaying: Bool) {
        let changed = episodeId != lastEpisodeId || isPlaying != lastIsPlaying
        lastEpisodeId = episodeId
        lastIsPlaying = isPlaying
        store?.quietProgressEpisodeId = isPlaying ? episodeId : nil
        store?.publishQuietProgress()
        if changed { objectWillChange.send() }
    }

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
