import Foundation
import PodcastCore

/// Builds `EpisodeListFacts` (PodcastCore filter/sort input) from app state.
extension PodcastStore {
    func listFacts(for episode: PodcastEpisode, feedTitle: String? = nil) -> EpisodeListFacts {
        let state = playbackStates[episode.id]
        let isDownloaded = downloads?.isDownloaded(episode) ?? false
        var size = episode.size
        if size <= 0, isDownloaded {
            size = downloads?.downloads.first { $0.id == episode.id }?.localFileByteSize() ?? 0
        }
        let duration = episode.durationSeconds > 0 ? episode.durationSeconds : (state?.durationSeconds ?? 0)
        return EpisodeListFacts(
            isPlayed: state?.isPlayed ?? false,
            positionSeconds: state?.positionSeconds ?? 0,
            isDownloaded: isDownloaded,
            isQueued: isInQueue(episode.id),
            isFavorite: isFavorite(episode.id),
            hasMedia: !(episode.downloadUrl ?? "").isEmpty,
            hasChapters: !episode.chapters.isEmpty || episode.podcastIndexChapterUrl != nil,
            pubDateEpochMs: episode.pubDateEpochMs,
            durationSeconds: duration,
            title: episode.title,
            feedTitle: feedTitle ?? feed(containingEpisodeId: episode.id).map { displayTitle(for: $0) } ?? "",
            sizeBytes: size
        )
    }

    /// Android Queue "Keep sorted": order the queue by the chosen sort (no-op when off).
    func keptSortedQueue(_ items: [PodcastEpisode]) -> [PodcastEpisode] {
        guard let order = settings?.queueKeepSortedOrder else { return items }
        return order.sorted(items) { listFacts(for: $0) }
    }

    /// Re-sort now (called when Keep sorted is switched on or its order changes).
    func applyQueueKeepSorted() {
        let sorted = keptSortedQueue(queue)
        if sorted.map(\.id) != queue.map(\.id) { queue = sorted }
    }
}

extension EpisodeListSortOrder {
    var label: String {
        switch self {
        case .dateNewOld: return String(localized: "Date (new → old)")
        case .dateOldNew: return String(localized: "Date (old → new)")
        case .durationShortLong: return String(localized: "Duration (short → long)")
        case .durationLongShort: return String(localized: "Duration (long → short)")
        case .titleAZ: return String(localized: "Episode title (A → Z)")
        case .titleZA: return String(localized: "Episode title (Z → A)")
        case .sizeSmallLarge: return String(localized: "Size (small → large)")
        case .sizeLargeSmall: return String(localized: "Size (large → small)")
        case .feedTitleAZ: return String(localized: "Podcast title (A → Z)")
        case .feedTitleZA: return String(localized: "Podcast title (Z → A)")
        }
    }
}

extension EpisodeFilterToken {
    var label: String {
        switch self {
        case .unplayed: return String(localized: "Unplayed")
        case .played: return String(localized: "Played")
        case .paused: return String(localized: "Paused")
        case .notPaused: return String(localized: "Not paused")
        case .downloaded: return String(localized: "Downloaded")
        case .notDownloaded: return String(localized: "Not downloaded")
        case .queued: return String(localized: "Queued")
        case .notQueued: return String(localized: "Not queued")
        case .favorite: return String(localized: "Favorite")
        case .notFavorite: return String(localized: "Not favorite")
        case .hasMedia: return String(localized: "Has media")
        case .noMedia: return String(localized: "No media")
        case .hasChapters: return String(localized: "Has chapters")
        case .noChapters: return String(localized: "No chapters")
        }
    }
}
