import Foundation

/// Builds every CarPlay list from the app stores without CarPlay/UIKit, so duplicate-feed
/// libraries can be tested. Robust to duplicate feed URLs (http/https, trailing slash) and duplicate
/// episode GUIDs across feeds: every subscribed feed is listed (no dedupe here), episodes keep their
/// own feed's title/artwork, and lookups never trap on duplicate keys.
@MainActor
struct CarPlayListBuilder {
    let store: PodcastStore
    var downloads: DownloadService?
    var settings: AppSettings?
    var currentEpisode: PodcastEpisode?
    var limit: Int

    /// Episode info in the context of `feed` (title/artwork from that feed, not a same-GUID twin).
    func info(_ ep: PodcastEpisode, feed: PodcastFeed?) -> CarPlayEpisodeInfo {
        let item = downloads?.downloads.first { $0.id == ep.id }
        return CarPlayEpisodeInfo(
            id: ep.id,
            title: ep.title,
            feedTitle: feed.map { store.displayTitle(for: $0) } ?? "",
            artwork: CarPlayBrowseModel.artworkURL(ep.artworkURL(feed: feed), feed?.imageUrl),
            pubDateEpochMs: ep.pubDateEpochMs,
            durationSeconds: ep.durationSeconds,
            positionSeconds: store.positionSeconds(for: ep.id),
            isPlayed: store.isPlayed(ep.id),
            isArchived: store.isArchived(ep.id),
            isFavorite: store.isFavorite(ep.id),
            isDownloaded: downloads?.isDownloaded(ep) ?? false,
            downloadedAtEpochMs: item?.downloadedAtEpochMs,
            byteSize: item?.knownByteSize(),
            feedId: feed?.id
        )
    }

    /// One entry per (feed, episode): duplicate GUIDs in different feeds both appear (Android keeps
    /// separate items per feed); an exact repeat inside the same feed is shown once.
    func allEpisodeInfos() -> [CarPlayEpisodeInfo] {
        var seen = Set<String>()
        var out: [CarPlayEpisodeInfo] = []
        for feed in store.feeds {
            for ep in feed.episodes where hasMedia(ep) && seen.insert(feed.id.uuidString + "|" + ep.id).inserted {
                out.append(info(ep, feed: feed))
            }
        }
        return out
    }

    /// Android `loadChildrenSynchronous` lists only items with media; a media-less entry cannot play.
    func hasMedia(_ ep: PodcastEpisode) -> Bool {
        CarPlayParity.hasMedia(downloadUrl: ep.downloadUrl, isDownloaded: downloads?.isDownloaded(ep) ?? false)
    }

    private func queueInfo(_ ep: PodcastEpisode) -> CarPlayEpisodeInfo {
        info(ep, feed: store.feed(containingEpisodeId: ep.id))
    }

    func row(_ e: CarPlayEpisodeInfo, showFeed: Bool = true) -> CarPlayRow {
        CarPlayRow(title: e.title, detail: CarPlayParity.detail(e, showFeed: showFeed), imageUrl: e.artwork,
                   target: .episode(e.id), progress: CarPlayParity.progress(e), feedId: e.feedId)
    }

    func queueSections() -> [(String?, [CarPlayRow])] {
        var sections: [(String?, [CarPlayRow])] = []
        if let cur = currentEpisode {
            sections.append((String(localized: "Currently playing"), [row(queueInfo(cur))]))
        }
        let q = store.queue.filter(hasMedia).prefix(limit).map { row(queueInfo($0)) }
        sections.append((sections.isEmpty ? nil : String(localized: "Queue"), q))
        return sections
    }

    func downloadRows(_ all: [CarPlayEpisodeInfo]) -> [CarPlayRow] {
        CarPlayParity.downloads(all, sort: settings?.downloadsSort ?? .newestFirst, limit: limit).map { row($0) }
    }

    func episodeRows(_ all: [CarPlayEpisodeInfo]) -> [CarPlayRow] {
        CarPlayParity.episodes(all, filter: settings?.allEpisodesFilter ?? .all,
                               sort: settings?.allEpisodesSort ?? .newestFirst, limit: limit).map { row($0) }
    }

    /// Every subscribed feed, including URL twins and feeds whose last parse failed (no episodes).
    func subscriptionRows() -> [CarPlayRow] {
        let unplayed = store.unplayedCountsByFeedId()
        let infos = store.feeds.map {
            CarPlayParity.FeedInfo(id: $0.id, title: store.displayTitle(for: $0), author: $0.author,
                                   unplayedCount: unplayed[$0.id] ?? 0, lastRefreshedEpochMs: $0.lastRefreshedAtEpochMs)
        }
        let feedsById = Dictionary(store.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return CarPlayParity.feeds(infos, sort: settings?.subscriptionsSort ?? .alphabetical, limit: limit).map { f in
            let feed = feedsById[f.id]
            return CarPlayRow(
                title: f.title,
                detail: f.unplayedCount > 0 ? String(localized: "\(f.unplayedCount) unplayed") : f.author,
                imageUrl: feed.flatMap { CarPlayBrowseModel.artworkURL($0.preferredDisplayArtworkURL, $0.imageUrl) },
                target: .feed(f.id)
            )
        }
    }

    func feedEpisodeRows(_ feedId: UUID) -> [CarPlayRow] {
        guard let feed = store.feeds.first(where: { $0.id == feedId }) else { return [] }
        var seen = Set<String>()
        let infos = feed.episodes.filter { hasMedia($0) && seen.insert($0.id).inserted }.map { info($0, feed: feed) }
        let global = settings?.feedEpisodeSort ?? .newestFirst
        let sort = store.feedSettings(for: feedId).resolvedEpisodeSort(global: global)
        return CarPlayParity.feedEpisodes(infos, sort: sort, filter: settings?.feedEpisodeFilter ?? .all, limit: limit)
            .map { row($0, showFeed: false) }
    }

    func upNextRows() -> [CarPlayRow] {
        // Same rule as CarPlayParity.upNext, but on the queue entries themselves so duplicate ids
        // keep their own episode (no id → episode lookup that collapses twins).
        let queue = store.queue.filter(hasMedia)
        let rest = CarPlayParity.upNext(queueIds: queue.map(\.id), currentId: currentEpisode?.id).count
        return queue.suffix(rest).prefix(limit).map { row(queueInfo($0)) }
    }

    /// Episode to play for a tapped row: the loaded one, then that row's own feed (so a same-GUID
    /// twin in another feed is not picked), then queue, then any feed.
    func episodeToPlay(id: String, feedId: UUID?) -> PodcastEpisode? {
        if currentEpisode?.id == id { return currentEpisode }
        if let feedId, let ep = store.feeds.first(where: { $0.id == feedId })?.episodes.first(where: { $0.id == id }) {
            return ep
        }
        return store.queue.first { $0.id == id } ?? store.feeds.lazy.flatMap(\.episodes).first { $0.id == id }
    }
}
