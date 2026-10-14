import SwiftUI

/// Android-parity long-press actions that every episode list shares through `EpisodeRow`'s
/// `.contextMenu`, so Queue, Inbox, Episodes, Downloads, History, Favorites, Home, Feed and Search
/// all get them.
/// Android refs: app/src/main/res/menu/feeditemlist_context.xml (remove_from_queue_item, remove_item,
/// reset_position) and queue_context.xml (move to top/bottom lives in EpisodeRow already).
struct EpisodeContextMenu: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let episode: PodcastEpisode

    var body: some View {
        // Android remove_from_queue_item: removing is allowed while the queue is locked (lock only blocks reorder).
        if store.isInQueue(episode.id) {
            Button(role: .destructive) {
                store.removeFromQueue(episode)
            } label: {
                Label("Remove from queue", systemImage: "text.badge.minus")
            }
            .accessibilityHint(String(localized: "Removes this episode from the queue. No confirmation. Does not delete the download or change progress."))
        }
        // Android remove_item (delete downloaded file).
        if downloads.isDownloaded(episode) {
            Button(role: .destructive) {
                downloads.delete(episode)
            } label: {
                Label("Delete download", systemImage: "trash")
            }
            .accessibilityHint(String(localized: "Deletes the downloaded file for this episode. No confirmation. Keeps the episode, its progress and its queue place."))
        }
        // Android reset_position: hidden for the episode that is playing now, because the player would overwrite it.
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
