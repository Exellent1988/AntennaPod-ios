import SwiftUI

/// Which list an episode row is shown in; drives Android's per-list menu visibility
/// (queue_context.xml is only added by QueueFragment; "go to podcast" is pointless on the feed page).
enum EpisodeListContext { case other, queue, feed }

private struct EpisodeListContextKey: EnvironmentKey {
    static let defaultValue: EpisodeListContext = .other
}

extension EnvironmentValues {
    var episodeListContext: EpisodeListContext {
        get { self[EpisodeListContextKey.self] }
        set { self[EpisodeListContextKey.self] = newValue }
    }
}

/// Android-parity long-press items shared by every list through `EpisodeRow`'s `.contextMenu`.
/// Android refs: app/src/main/res/menu/feeditemlist_context.xml and FeedItemMenuHandler.onPrepareMenu
/// (remove_from_queue_item if queued; remove_item if downloaded or downloading, download_item otherwise;
/// reset_position if position != 0).
struct EpisodeContextMenu: View {
    enum Part { case removeFromQueue, download, resetPosition }

    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var nowPlaying: NowPlayingListState
    // Not observed: list rows show stored progress (Android FeedMedia.position), see NowPlayingListState.
    private var playback: PlaybackService { nowPlaying.playback }
    @EnvironmentObject private var downloads: DownloadService
    let episode: PodcastEpisode
    let part: Part

    var body: some View {
        switch part {
        case .removeFromQueue:
            // Removing is allowed while the queue is locked (lock only blocks reorder).
            if store.isInQueue(episode.id) {
                Button(role: .destructive) {
                    store.removeFromQueue(episode)
                } label: {
                    Label("Remove from queue", systemImage: "text.badge.minus")
                }
                .accessibilityHint(String(localized: "Removes this episode from the queue. No confirmation. Does not delete the download or change progress."))
            }
        case .download:
            if EpisodeDownloadActions.canManageDownload(for: episode) {
                if downloads.inProgress.contains(episode.id) {
                    Button(role: .destructive) {
                        downloads.cancelDownload(episode)
                    } label: {
                        Label("Cancel download", systemImage: "xmark.circle")
                    }
                } else if downloads.isDownloaded(episode) {
                    Button(role: .destructive) {
                        downloads.delete(episode)
                    } label: {
                        Label("Delete download", systemImage: "trash")
                    }
                    .accessibilityHint(String(localized: "Deletes the downloaded file for this episode. No confirmation. Keeps the episode, its progress and its queue place."))
                } else {
                    Button {
                        Task { await downloads.download(episode) }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
        case .resetPosition:
            // Hidden for the episode that is playing now, because the player would overwrite it.
            if store.positionSeconds(for: episode.id) > 0, playback.currentEpisode?.id != episode.id {
                Button {
                    store.saveProgress(episodeId: episode.id, positionSeconds: 0, durationSeconds: 0)
                } label: {
                    Label("Reset playback position", systemImage: "gobackward")
                }
                .accessibilityHint(String(localized: "Sets the saved position of this episode back to the start. No confirmation. Does not mark played or unplayed."))
            }
        }
    }
}
