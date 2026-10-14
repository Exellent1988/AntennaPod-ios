import SwiftUI

/// Shared **Download / Cancel / Delete** control for Full player secondary + mini player ⋯.
///
/// Mirrors Full Player semantics exactly via existing `DownloadService` APIs only:
/// - **Download** → `download(_:)` (manual Wi‑Fi gate inside the service)
/// - **Cancel download** → `cancelDownload` while in-flight
/// - **Delete download** → caller shows `confirmationDialog`, then `delete(_:)` (local offline
///   file only — keeps played / queue / favorites)
///
/// Hidden for local-folder / `file://` enclosures (`canManageDownload`).
@MainActor
enum EpisodeDownloadActions {
    /// True when the episode has a remote enclosure (not a local-folder `file://`).
    static func canManageDownload(for episode: PodcastEpisode) -> Bool {
        guard let raw = episode.downloadUrl, !raw.isEmpty else { return false }
        return !LocalFolderFeed.isLocalFileDownloadURL(raw)
    }

    static func accessibilityLabel(for episode: PodcastEpisode, downloads: DownloadService) -> String {
        if downloads.inProgress.contains(episode.id) {
            return String(localized: "Cancel download")
        }
        if downloads.isDownloaded(episode) {
            return String(localized: "Delete download")
        }
        return String(localized: "Download")
    }

    static func accessibilityHint(for episode: PodcastEpisode, downloads: DownloadService) -> String {
        if downloads.isWaitingDownload(episodeId: episode.id) {
            return String(localized: "Cancels this waiting download immediately. No confirmation. Does not delete completed offline files, and does not affect played status, queue, favorites, or archive. Distinct from Cancel all downloads and from Delete download.")
        }
        if downloads.inProgress.contains(episode.id) {
            return String(localized: "Cancels this in-progress download immediately. No confirmation. Does not delete completed offline files, and does not affect played status, queue, favorites, or archive. Distinct from Cancel all downloads and from Delete download.")
        }
        if downloads.isDownloaded(episode) {
            return String(localized: "Asks for confirmation, then deletes the local offline file for this episode; keeps played status, queue membership, favorites, and archive state")
        }
        return String(localized: "Downloads this episode for offline playback. No confirmation. Manual download Wi‑Fi only, parallel-download cap, and storage limit still apply when enabled.")
    }

    /// Single Button control. Use in Full secondary HStack or nest inside mini ⋯ `Menu`.
    /// Returns `EmptyView` when `canManageDownload` is false (local-folder / missing URL).
    @ViewBuilder
    static func button(
        episode: PodcastEpisode,
        downloads: DownloadService,
        onRequestDeleteDownload: @escaping (PodcastEpisode) -> Void
    ) -> some View {
        if canManageDownload(for: episode) {
            Button {
                if downloads.inProgress.contains(episode.id) {
                    downloads.cancelDownload(episode)
                } else if downloads.isDownloaded(episode) {
                    // Same path as Downloads tab swipe Delete — confirm first.
                    onRequestDeleteDownload(episode)
                } else {
                    Task { await downloads.download(episode) }
                }
            } label: {
                if downloads.isWaitingDownload(episodeId: episode.id) {
                    Label("Waiting", systemImage: "clock")
                } else if downloads.inProgress.contains(episode.id) {
                    Label("Cancel download", systemImage: "xmark.circle")
                } else if downloads.isDownloaded(episode) {
                    Label("Delete download", systemImage: "trash")
                } else {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .tint(
                downloads.isDownloaded(episode) && !downloads.inProgress.contains(episode.id)
                    ? .red
                    : nil
            )
            .accessibilityLabel(accessibilityLabel(for: episode, downloads: downloads))
            .accessibilityHint(accessibilityHint(for: episode, downloads: downloads))
        }
    }
}
