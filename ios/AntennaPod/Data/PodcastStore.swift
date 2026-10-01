import Foundation

@MainActor
final class PodcastStore: ObservableObject {
    @Published var feeds: [PodcastFeed] = [] {
        didSet { PodcastPersistence.saveFeeds(feeds) }
    }
    @Published var queue: [PodcastEpisode] = [] {
        didSet { PodcastPersistence.saveQueue(queue) }
    }
    /// Episode id → position / played. Published so episode rows refresh.
    @Published var playbackStates: [String: EpisodePlaybackState] = [:] {
        didSet { PodcastPersistence.savePlaybackStates(playbackStates) }
    }
    /// Per-subscription overrides keyed by feed id (`feed-settings.json`).
    @Published var feedSettingsById: [UUID: FeedSettings] = [:] {
        didSet { PodcastPersistence.saveFeedSettings(feedSettingsById) }
    }
    /// Episode id → favorited-at epoch ms (`favorites.json` side map).
    @Published var favoriteAtById: [String: Int64] = [:] {
        didSet { PodcastPersistence.saveFavorites(favoriteAtById) }
    }
    /// Feed id → tag names (`feed-tags.json` side map). Tags exist only while assigned.
    @Published var tagsByFeedId: [UUID: [String]] = [:] {
        didSet { PodcastPersistence.saveFeedTags(tagsByFeedId) }
    }
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var opmlImport = OpmlImportState()

    /// Optional settings for stamping last feed-refresh time after `refreshAllFeeds()`.
    weak var settings: AppSettings?
    /// Optional downloads for auto-download enqueue after refresh / auto-delete after play.
    weak var downloads: DownloadService?
    /// Optional playback so auto-delete can skip while a local file is still the active player item.
    weak var playback: PlaybackService?

    /// Episode ids marked played while still loaded as the local player item; flushed when playback leaves them.
    private var pendingAutoDeleteIds: Set<String> = []

    private let repository = FeedRepository()

    init() {
        feeds = PodcastPersistence.loadFeeds()
        queue = PodcastPersistence.loadQueue()
        playbackStates = PodcastPersistence.loadPlaybackStates()
        feedSettingsById = PodcastPersistence.loadFeedSettings()
        favoriteAtById = PodcastPersistence.loadFavorites()
        tagsByFeedId = PodcastPersistence.loadFeedTags()
    }

    func subscribe(feedUrl: String) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            var feed = try await repository.fetchAndParse(feedUrl: feedUrl)
            feed.feedUrl = feedUrl
            if let index = feeds.firstIndex(where: { $0.feedUrl == feedUrl }) {
                feed.id = feeds[index].id // keep stable identity across refresh
                feeds[index] = feed
            } else {
                feeds.append(feed)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unsubscribe(_ feed: PodcastFeed) {
        feeds.removeAll { $0.id == feed.id }
        feedSettingsById.removeValue(forKey: feed.id)
        tagsByFeedId.removeValue(forKey: feed.id)
        let ids = Set(feed.episodes.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        for id in ids {
            playbackStates.removeValue(forKey: id)
            favoriteAtById.removeValue(forKey: id)
        }
    }

    // MARK: - Per-feed settings

    func feedSettings(for feedId: UUID) -> FeedSettings {
        feedSettingsById[feedId] ?? .default
    }

    func setFeedSettings(_ settings: FeedSettings, for feedId: UUID) {
        if settings.isDefault {
            feedSettingsById.removeValue(forKey: feedId)
        } else {
            feedSettingsById[feedId] = settings
        }
    }

    func updateFeedSettings(for feedId: UUID, _ mutate: (inout FeedSettings) -> Void) {
        var current = feedSettings(for: feedId)
        mutate(&current)
        setFeedSettings(current, for: feedId)
    }

    // MARK: - Tags / folders

    /// Tags assigned to a feed (sorted, unique).
    func tags(for feedId: UUID) -> [String] {
        FeedTags.uniqueSorted(tagsByFeedId[feedId] ?? [])
    }

    /// All tag names currently in use across subscriptions (sorted).
    var allTags: [String] {
        FeedTags.uniqueSorted(tagsByFeedId.values.flatMap { $0 })
    }

    func setTags(_ tags: [String], for feedId: UUID) {
        let cleaned = FeedTags.uniqueSorted(tags)
        if cleaned.isEmpty {
            tagsByFeedId.removeValue(forKey: feedId)
        } else {
            tagsByFeedId[feedId] = cleaned
        }
    }

    @discardableResult
    func addTag(_ raw: String, to feedId: UUID) -> Bool {
        guard let name = FeedTags.normalize(raw) else { return false }
        var current = tags(for: feedId)
        if current.contains(where: { FeedTags.equal($0, name) }) {
            return false
        }
        // Prefer existing casing from the global vocabulary when matching.
        let display = allTags.first(where: { FeedTags.equal($0, name) }) ?? name
        current.append(display)
        setTags(current, for: feedId)
        return true
    }

    func removeTag(_ raw: String, from feedId: UUID) {
        guard let name = FeedTags.normalize(raw) else { return }
        let current = tags(for: feedId).filter { !FeedTags.equal($0, name) }
        setTags(current, for: feedId)
    }

    /// Rename a tag everywhere it is used. Empty / duplicate target removes or merges.
    func renameTag(from oldRaw: String, to newRaw: String) {
        guard let oldName = FeedTags.normalize(oldRaw) else { return }
        guard let newName = FeedTags.normalize(newRaw) else {
            deleteTag(oldName)
            return
        }
        if FeedTags.equal(oldName, newName) { return }
        let display = allTags.first(where: { FeedTags.equal($0, newName) }) ?? newName
        var next = tagsByFeedId
        for (feedId, list) in next {
            var updated: [String] = []
            for tag in list {
                if FeedTags.equal(tag, oldName) {
                    if !updated.contains(where: { FeedTags.equal($0, display) }) {
                        updated.append(display)
                    }
                } else if !updated.contains(where: { FeedTags.equal($0, tag) }) {
                    updated.append(tag)
                }
            }
            next[feedId] = FeedTags.uniqueSorted(updated)
            if next[feedId]?.isEmpty == true {
                next.removeValue(forKey: feedId)
            }
        }
        tagsByFeedId = next
    }

    /// Delete a tag from every feed (last use → tag disappears from `allTags`).
    func deleteTag(_ raw: String) {
        guard let name = FeedTags.normalize(raw) else { return }
        let snapshot = tagsByFeedId
        for (feedId, list) in snapshot {
            setTags(list.filter { !FeedTags.equal($0, name) }, for: feedId)
        }
    }

    func feeds(withTag raw: String) -> [PodcastFeed] {
        guard let name = FeedTags.normalize(raw) else { return [] }
        return feeds.filter { feed in
            tags(for: feed.id).contains(where: { FeedTags.equal($0, name) })
        }
    }

    var untaggedFeeds: [PodcastFeed] {
        feeds.filter { tags(for: $0.id).isEmpty }
    }

    func refresh(_ feed: PodcastFeed) async {
        guard !feed.feedUrl.isEmpty else {
            return
        }
        let existingIds = Set(feed.episodes.map(\.id))
        let wasSubscribed = feeds.contains(where: { $0.feedUrl == feed.feedUrl })
        await subscribe(feedUrl: feed.feedUrl)
        if wasSubscribed, let updated = feeds.first(where: { $0.feedUrl == feed.feedUrl }) {
            let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
            if !newcomers.isEmpty {
                await NewEpisodeNotificationCoordinator.handleNewEpisodes(
                    [NewEpisodeBatch(feedTitle: updated.title, feedId: updated.id, feedUrl: updated.feedUrl, episodes: newcomers)],
                    settings: settings,
                    store: self
                )
            }
        }
        await AutoDownloadCoordinator.enqueueAfterRefresh(
            store: self,
            downloads: downloads,
            settings: settings
        )
    }

    func enqueue(_ episode: PodcastEpisode) {
        if !queue.contains(where: { $0.id == episode.id }) {
            queue.append(episode)
        }
    }

    func removeFromQueue(_ episode: PodcastEpisode) {
        queue.removeAll { $0.id == episode.id }
    }

    // MARK: - Playback progress / played

    func playbackState(for episodeId: String) -> EpisodePlaybackState {
        playbackStates[episodeId] ?? .empty()
    }

    func isPlayed(_ episodeId: String) -> Bool {
        playbackStates[episodeId]?.isPlayed ?? false
    }

    func positionSeconds(for episodeId: String) -> Double {
        playbackStates[episodeId]?.positionSeconds ?? 0
    }

    /// Persist continuous progress while listening (does not flip played).
    func saveProgress(episodeId: String, positionSeconds: Double, durationSeconds: Double) {
        var state = playbackState(for: episodeId)
        state.positionSeconds = max(0, positionSeconds)
        if durationSeconds.isFinite, durationSeconds > 0 {
            state.durationSeconds = durationSeconds
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        state.updatedAtEpochMs = nowMs
        // Stamp History sort key while listening (throttle not needed — didSet already persists).
        if positionSeconds > 1 || state.isPlayed {
            state.lastPlayedAtEpochMs = nowMs
        }
        playbackStates[episodeId] = state
    }

    /// AntennaPod-like: mark played and reset position for a clean resume-from-start later.
    /// When auto-delete-after-playing is on, removes the local download file (keeps the episode row).
    func markPlayed(_ episodeId: String, removeFromQueue: Bool = true) {
        var state = playbackState(for: episodeId)
        state.isPlayed = true
        state.positionSeconds = 0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        state.updatedAtEpochMs = nowMs
        state.lastPlayedAtEpochMs = nowMs
        playbackStates[episodeId] = state
        if removeFromQueue {
            queue.removeAll { $0.id == episodeId }
        }
        enqueueAutoDeleteAfterPlaying(episodeId)
    }

    func markUnplayed(_ episodeId: String) {
        var state = playbackState(for: episodeId)
        state.isPlayed = false
        state.updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        playbackStates[episodeId] = state
        pendingAutoDeleteIds.remove(episodeId)
    }

    func togglePlayed(_ episodeId: String) {
        if isPlayed(episodeId) {
            markUnplayed(episodeId)
        } else {
            markPlayed(episodeId)
        }
    }

    /// Stamp History sort key when playback starts (even before first progress persist).
    func touchLastPlayed(_ episodeId: String) {
        var state = playbackState(for: episodeId)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        state.updatedAtEpochMs = nowMs
        state.lastPlayedAtEpochMs = nowMs
        playbackStates[episodeId] = state
    }

    /// Next queue item after `episodeId`, or the head of the queue if that id is gone.
    func nextQueueEpisode(after episodeId: String) -> PodcastEpisode? {
        if let index = queue.firstIndex(where: { $0.id == episodeId }) {
            let next = index + 1
            if next < queue.count {
                return queue[next]
            }
            return nil
        }
        return queue.first
    }

    /// Feed that owns the episode (for Now Playing artist / artwork).
    func feed(containingEpisodeId episodeId: String) -> PodcastFeed? {
        feeds.first { feed in
            feed.episodes.contains { $0.id == episodeId }
        }
    }

    /// Episode from subscriptions (preferred over a stale queue / player copy for chapters).
    func episode(id episodeId: String) -> PodcastEpisode? {
        for feed in feeds {
            if let episode = feed.episodes.first(where: { $0.id == episodeId }) {
                return episode
            }
        }
        return queue.first { $0.id == episodeId }
    }

    /// Persist chapters onto the subscribed / queued episode after a remote Podcast Index fetch.
    func updateChapters(episodeId: String, chapters: [PodcastChapter]) {
        guard !chapters.isEmpty else { return }
        if let fi = feeds.firstIndex(where: { $0.episodes.contains { $0.id == episodeId } }) {
            if let ei = feeds[fi].episodes.firstIndex(where: { $0.id == episodeId }) {
                feeds[fi].episodes[ei].chapters = chapters
            }
        }
        if let qi = queue.firstIndex(where: { $0.id == episodeId }) {
            queue[qi].chapters = chapters
        }
    }

    // MARK: - Auto-delete after playing

    /// Call when playback leaves an episode (end, stop, or switch) so a deferred auto-delete can run.
    func flushAutoDeleteAfterPlaying(for episodeId: String) {
        guard pendingAutoDeleteIds.remove(episodeId) != nil else { return }
        performAutoDeleteAfterPlaying(episodeId)
    }

    private func enqueueAutoDeleteAfterPlaying(_ episodeId: String) {
        guard settings?.autoDeleteAfterPlaying == true else { return }
        guard !isFavorite(episodeId) else {
            pendingAutoDeleteIds.remove(episodeId)
            return
        }
        // Don't delete the file while AVPlayer is still using that local URL.
        if playback?.shouldBlockAutoDelete(for: episodeId) == true {
            pendingAutoDeleteIds.insert(episodeId)
            return
        }
        performAutoDeleteAfterPlaying(episodeId)
    }

    private func performAutoDeleteAfterPlaying(_ episodeId: String) {
        guard settings?.autoDeleteAfterPlaying == true else { return }
        // Favorited / starred episodes keep their offline file.
        guard !isFavorite(episodeId) else { return }
        guard let downloads else { return }
        let episode: PodcastEpisode?
        if let item = downloads.downloads.first(where: { $0.id == episodeId }) {
            episode = item.episode
        } else {
            episode = self.episode(id: episodeId)
        }
        guard let episode, downloads.isDownloaded(episode) else { return }
        // File + catalog only; feeds / playbackStates (played) stay.
        downloads.delete(episode)
    }

    // MARK: - Inbox (new / unplayed)

    /// Unplayed episodes across all subscriptions, newest first (by `pubDateEpochMs`).
    /// "New" matches playback state: not `isPlayed` (in-progress still counts as inbox).
    var inboxEpisodes: [InboxEpisode] {
        var items: [InboxEpisode] = []
        for feed in feeds {
            for episode in feed.episodes where !isPlayed(episode.id) {
                items.append(InboxEpisode(episode: episode, feedTitle: feed.title))
            }
        }
        items.sort { lhs, rhs in
            let l = lhs.episode.pubDateEpochMs ?? Int64.min
            let r = rhs.episode.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title) == .orderedAscending
        }
        return items
    }

    // MARK: - All Episodes (catalog)

    /// Soft cap for All Episodes (newest by pubDate). Keeps List honest without lazy paging.
    static let allEpisodesSoftLimit = 500

    /// All episodes across subscriptions, newest `pubDateEpochMs` first (soft-capped).
    /// Distinct from Inbox (unplayed only): played / in-progress are included.
    var allEpisodes: [InboxEpisode] {
        var items: [InboxEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                items.append(InboxEpisode(episode: episode, feedTitle: feed.title))
            }
        }
        items.sort { lhs, rhs in
            let l = lhs.episode.pubDateEpochMs ?? Int64.min
            let r = rhs.episode.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title) == .orderedAscending
        }
        if items.count > Self.allEpisodesSoftLimit {
            return Array(items.prefix(Self.allEpisodesSoftLimit))
        }
        return items
    }

    // MARK: - Home sections

    /// In-progress (not played) episodes with meaningful progress, newest `lastPlayedAt` first.
    var continueListeningEpisodes: [HistoryEpisode] {
        historyEpisodes.filter { item in
            let state = playbackState(for: item.episode.id)
            return !state.isPlayed && state.positionSeconds > 1
        }
    }

    /// Subscriptions ordered by newest episode `pubDateEpochMs` (proxy for recently updated).
    var recentlyUpdatedFeeds: [PodcastFeed] {
        feeds.sorted { lhs, rhs in
            let l = lhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
            let r = rhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
            if l != r { return l > r }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }


    // MARK: - Favorites (starred)

    func isFavorite(_ episodeId: String) -> Bool {
        favoriteAtById[episodeId] != nil
    }

    func toggleFavorite(_ episodeId: String) {
        if isFavorite(episodeId) {
            favoriteAtById.removeValue(forKey: episodeId)
            // No auto-delete on unfavorite; user already marked played earlier if applicable.
        } else {
            favoriteAtById[episodeId] = Int64(Date().timeIntervalSince1970 * 1000)
            // Starred while a delete was deferred — cancel it.
            pendingAutoDeleteIds.remove(episodeId)
        }
    }

    /// Starred episodes across feeds, newest favorited first.
    var favoriteEpisodes: [FavoriteEpisode] {
        var items: [FavoriteEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                guard let at = favoriteAtById[episode.id] else { continue }
                items.append(
                    FavoriteEpisode(
                        episode: episode,
                        feedTitle: feed.title,
                        favoritedAtEpochMs: at
                    )
                )
            }
        }
        // Queue-only copies that were starred (rare).
        let knownIds = Set(items.map(\.id))
        for episode in queue where !knownIds.contains(episode.id) {
            guard let at = favoriteAtById[episode.id] else { continue }
            let title = feed(containingEpisodeId: episode.id)?.title ?? ""
            items.append(
                FavoriteEpisode(
                    episode: episode,
                    feedTitle: title,
                    favoritedAtEpochMs: at
                )
            )
        }
        items.sort { lhs, rhs in
            if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                return lhs.favoritedAtEpochMs > rhs.favoritedAtEpochMs
            }
            return lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title) == .orderedAscending
        }
        return items
    }

    // MARK: - History (played / in-progress)

    /// Episodes marked played or with meaningful progress, newest `lastPlayedAt` first.
    var historyEpisodes: [HistoryEpisode] {
        var items: [HistoryEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                let state = playbackState(for: episode.id)
                guard state.belongsInHistory else { continue }
                let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
                items.append(
                    HistoryEpisode(
                        episode: episode,
                        feedTitle: feed.title,
                        lastPlayedAtEpochMs: lastPlayed
                    )
                )
            }
        }
        // Include queue-only copies that still have playback state (rare but possible).
        let knownIds = Set(items.map(\.id))
        for episode in queue where !knownIds.contains(episode.id) {
            let state = playbackState(for: episode.id)
            guard state.belongsInHistory else { continue }
            let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
            let title = feed(containingEpisodeId: episode.id)?.title ?? ""
            items.append(
                HistoryEpisode(
                    episode: episode,
                    feedTitle: title,
                    lastPlayedAtEpochMs: lastPlayed
                )
            )
        }
        items.sort { lhs, rhs in
            if lhs.lastPlayedAtEpochMs != rhs.lastPlayedAtEpochMs {
                return lhs.lastPlayedAtEpochMs > rhs.lastPlayedAtEpochMs
            }
            return lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title) == .orderedAscending
        }
        return items
    }

    /// Drop progress / played flags so the episode leaves History (episode row itself stays).
    func removeFromHistory(_ episodeId: String) {
        playbackStates.removeValue(forKey: episodeId)
        pendingAutoDeleteIds.remove(episodeId)
    }

    /// Refresh every subscribed feed (Inbox pull-to-refresh + auto Keep updated). Continues on per-feed errors.
    func refreshAllFeeds() async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        let snapshot = feeds
        var newBatches: [NewEpisodeBatch] = []
        for feed in snapshot where !feed.feedUrl.isEmpty {
            guard feedSettings(for: feed.id).participatesInBulkRefresh else { continue }
            let existingIds = Set(feed.episodes.map(\.id))
            do {
                try await subscribeQuietly(feedUrl: feed.feedUrl)
                if let updated = feeds.first(where: { $0.feedUrl == feed.feedUrl }) {
                    let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
                    if !newcomers.isEmpty {
                        newBatches.append(
                            NewEpisodeBatch(
                                feedTitle: updated.title,
                                feedId: updated.id,
                                feedUrl: updated.feedUrl,
                                episodes: newcomers
                            )
                        )
                    }
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
        // Stamp even if some feeds failed — avoids hammering on every foreground.
        settings?.markFeedRefreshCompleted()
        await NewEpisodeNotificationCoordinator.handleNewEpisodes(newBatches, settings: settings, store: self)
        await AutoDownloadCoordinator.enqueueAfterRefresh(
            store: self,
            downloads: downloads,
            settings: settings
        )
    }

    // MARK: - Library search (local only)

    /// Matching subscriptions by feed title or feed description (case-insensitive).
    func matchingFeeds(query: String) -> [PodcastFeed] {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }
        return feeds.filter { feed in
            Self.matches(feed.title, query: q)
                || Self.matches(feed.descriptionText, query: q)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Matching episodes across subscriptions by episode title (feeds listed separately).
    func matchingEpisodes(query: String) -> [LibraryEpisodeHit] {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }
        var hits: [LibraryEpisodeHit] = []
        for feed in feeds {
            for episode in feed.episodes where Self.matches(episode.title, query: q) {
                hits.append(
                    LibraryEpisodeHit(
                        episode: episode,
                        feedTitle: feed.title,
                        feedId: feed.id
                    )
                )
            }
        }
        hits.sort { lhs, rhs in
            let titleCmp = lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title)
            if titleCmp != .orderedSame { return titleCmp == .orderedAscending }
            return lhs.feedTitle.localizedCaseInsensitiveCompare(rhs.feedTitle) == .orderedAscending
        }
        return hits
    }

    private static func normalizedQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ value: String?, query: String) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.localizedCaseInsensitiveContains(query)
    }

    // MARK: - OPML import / export

    func exportOpmlXML() -> String {
        OpmlWriter.writeDocument(feeds: feeds)
    }

    func exportOpmlTemporaryFile() throws -> URL {
        try OpmlWriter.writeTemporaryFile(feeds: feeds)
    }

    /// Parse OPML and subscribe each feed URL via the existing fetch/parse pipeline.
    /// Skips URLs already in `feeds`. Records per-URL errors without aborting the batch.
    func importOpml(data: Data) async {
        lastError = nil
        var state = OpmlImportState(isImporting: true)
        opmlImport = state
        do {
            let outlines = try OpmlReader.parse(data: data)
            // Deduplicate by xmlUrl (first wins)
            var seen = Set<String>()
            var unique: [OpmlOutline] = []
            for o in outlines {
                let key = o.xmlUrl.lowercased()
                if seen.insert(key).inserted {
                    unique.append(o)
                }
            }
            state.total = unique.count
            opmlImport = state
            var subscribed = Set(feeds.map { $0.feedUrl.lowercased() })

            for outline in unique {
                state.currentTitle = outline.text
                opmlImport = state
                let urlKey = outline.xmlUrl.lowercased()
                if subscribed.contains(urlKey) {
                    state.skipped += 1
                    state.completed += 1
                    opmlImport = state
                    continue
                }
                do {
                    try await subscribeQuietly(feedUrl: outline.xmlUrl)
                    subscribed.insert(urlKey)
                    state.succeeded += 1
                } catch {
                    state.failures.append(
                        OpmlImportFailure(
                            title: outline.text,
                            url: outline.xmlUrl,
                            error: error.localizedDescription
                        )
                    )
                }
                state.completed += 1
                opmlImport = state
            }
        } catch {
            lastError = error.localizedDescription
        }
        state.currentTitle = nil
        state.isImporting = false
        opmlImport = state
    }

    /// Subscribe without flipping the global `isLoading` overlay (used by OPML batch / refresh).
    func subscribeQuietly(feedUrl: String) async throws {
        var feed = try await repository.fetchAndParse(feedUrl: feedUrl)
        feed.feedUrl = feedUrl
        if let index = feeds.firstIndex(where: { $0.feedUrl == feedUrl }) {
            feed.id = feeds[index].id // keep stable identity across refresh
            feeds[index] = feed
        } else {
            feeds.append(feed)
        }
    }

}

