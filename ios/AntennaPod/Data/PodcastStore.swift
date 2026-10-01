import Foundation

@MainActor
final class PodcastStore: ObservableObject {
    @Published var feeds: [PodcastFeed] = [] {
        didSet { PodcastPersistence.saveFeeds(feeds) }
    }
    @Published var queue: [PodcastEpisode] = [] {
        didSet {
            PodcastPersistence.saveQueue(queue)
            // Queue changes can affect Continue listening / widget context.
            publishWidgetSnapshot()
        }
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
    /// Episode id → archived-at epoch ms (`archived.json` side map). Archived ≠ played.
    @Published var archivedAtById: [String: Int64] = [:] {
        didSet { PodcastPersistence.saveArchived(archivedAtById) }
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
        archivedAtById = PodcastPersistence.loadArchived()
        tagsByFeedId = PodcastPersistence.loadFeedTags()
        LocalFolderBookmarkStore.reloadFromPersistence()
        rescanLocalFolderFeedsBestEffort()
        publishWidgetSnapshot()
    }

    /// Reload all Application Support maps after a data backup import (didSet re-persists).
    func reloadFromPersistence() {
        feeds = PodcastPersistence.loadFeeds()
        queue = PodcastPersistence.loadQueue()
        playbackStates = PodcastPersistence.loadPlaybackStates()
        feedSettingsById = PodcastPersistence.loadFeedSettings()
        favoriteAtById = PodcastPersistence.loadFavorites()
        archivedAtById = PodcastPersistence.loadArchived()
        tagsByFeedId = PodcastPersistence.loadFeedTags()
        LocalFolderBookmarkStore.reloadFromPersistence()
        pendingAutoDeleteIds = []
        lastError = nil
        rescanLocalFolderFeedsBestEffort()
        publishWidgetSnapshot()
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

    /// Remove a subscription.
    /// Clears the feed from the list, per-feed settings, tags, queue items from this feed,
    /// and favorites / archive / playback-history entries for its episodes.
    /// Local-folder feeds also release the security-scoped bookmark.
    /// Does **not** delete downloaded episode files (Downloads catalog / offline media kept).
    func unsubscribe(_ feed: PodcastFeed) {
        if LocalFolderFeed.isLocalFolderFeed(feed) {
            LocalFolderBookmarkStore.release(feedId: feed.id)
        }
        feeds.removeAll { $0.id == feed.id }
        feedSettingsById.removeValue(forKey: feed.id)
        tagsByFeedId.removeValue(forKey: feed.id)
        let ids = Set(feed.episodes.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        for id in ids {
            playbackStates.removeValue(forKey: id)
            favoriteAtById.removeValue(forKey: id)
            archivedAtById.removeValue(forKey: id)
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
        if LocalFolderFeed.isLocalFolderFeed(feed) {
            await refreshLocalFolderFeed(feed)
            return
        }
        let existingIds = Set(feed.episodes.map(\.id))
        let wasSubscribed = feeds.contains(where: { $0.feedUrl == feed.feedUrl })
        await subscribe(feedUrl: feed.feedUrl)
        if wasSubscribed, let updated = feeds.first(where: { $0.feedUrl == feed.feedUrl }) {
            let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
            if !newcomers.isEmpty {
                let batches = [
                    NewEpisodeBatch(
                        feedTitle: updated.title,
                        feedId: updated.id,
                        feedUrl: updated.feedUrl,
                        episodes: newcomers
                    )
                ]
                await NewEpisodeNotificationCoordinator.handleNewEpisodes(
                    batches,
                    settings: settings,
                    store: self
                )
                await NewEpisodeActionCoordinator.apply(
                    batches,
                    store: self,
                    downloads: downloads,
                    settings: settings
                )
            }
        }
        await AutoDownloadCoordinator.enqueueAfterRefresh(
            store: self,
            downloads: downloads,
            settings: settings
        )
    }

    func isInQueue(_ episodeId: String) -> Bool {
        queue.contains { $0.id == episodeId }
    }

    func enqueue(_ episode: PodcastEpisode) {
        if !queue.contains(where: { $0.id == episode.id }) {
            queue.append(episode)
        }
    }

    /// AntennaPod-style **Play Next**: place `episode` immediately after the currently
    /// playing queue item (or at the head if nothing is playing / current is not queued).
    /// If already in the queue, moves it (no duplicate). Persists via `queue` `didSet`.
    ///
    /// Continuous playback uses `nextQueueEpisode(after:)`: when current *is* in the queue,
    /// Play Next becomes the auto-next item; when current is *not* queued, head-of-queue is
    /// already what auto-next uses after finish (same honesty as append when current not queued).
    func playNext(_ episode: PodcastEpisode, currentlyPlayingId: String?) {
        queue.removeAll { $0.id == episode.id }
        let insertIndex: Int
        if let playingId = currentlyPlayingId,
           let index = queue.firstIndex(where: { $0.id == playingId }) {
            insertIndex = index + 1
        } else {
            insertIndex = 0
        }
        queue.insert(episode, at: min(insertIndex, queue.count))
    }

    func removeFromQueue(_ episode: PodcastEpisode) {
        queue.removeAll { $0.id == episode.id }
    }

    /// Drag-reorder queue rows (List `onMove`). Persists via `queue` `didSet`.
    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    /// AntennaPod-style **Move to top**: place a queued episode at **index 0** (literal head
    /// of the queue list — same as Android `queue.add(0, …)`). Distinct from **Play Next**,
    /// which inserts after the currently playing item. No-op if not queued or already first.
    /// Reuses `moveQueue` so persistence stays one source of truth (`queue` `didSet`).
    func moveQueueItemToTop(_ episode: PodcastEpisode) {
        guard let index = queue.firstIndex(where: { $0.id == episode.id }), index > 0 else { return }
        moveQueue(from: IndexSet(integer: index), to: 0)
    }

    /// AntennaPod-style **Move to bottom**: place a queued episode at the **end** of the list.
    /// No-op if not queued or already last. Reuses `moveQueue` → `queue` `didSet`.
    func moveQueueItemToBottom(_ episode: PodcastEpisode) {
        guard let index = queue.firstIndex(where: { $0.id == episode.id }),
              index < queue.count - 1 else { return }
        moveQueue(from: IndexSet(integer: index), to: queue.count)
    }

    /// Remove every episode from the queue. Persists via `queue` `didSet`.
    /// Does not stop playback, mark played, or delete downloads — only clears queue entries.
    func clearQueue() {
        queue = []
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
        publishWidgetSnapshot()
    }

    /// AntennaPod-like: mark played and reset position for a clean resume-from-start later.
    /// When auto-delete-after-playing is on, removes the local download file (keeps the episode row).
    /// Counts a successful mark-played for the optional App Store rating prompt when newly played.
    func markPlayed(_ episodeId: String, removeFromQueue: Bool = true) {
        let wasPlayed = isPlayed(episodeId)
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
        if !wasPlayed {
            RatingPromptCoordinator.recordSuccessfulMarkPlayed(settings: settings)
        }
        publishWidgetSnapshot()
    }

    func markUnplayed(_ episodeId: String) {
        var state = playbackState(for: episodeId)
        state.isPlayed = false
        state.updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        playbackStates[episodeId] = state
        pendingAutoDeleteIds.remove(episodeId)
        publishWidgetSnapshot()
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

    /// Unplayed, non-archived episodes across all subscriptions, newest first (by `pubDateEpochMs`).
    /// "New" matches playback state: not `isPlayed` (in-progress still counts as inbox). Archived are hidden from Inbox (and thus Home New preview).
    /// Inbox tab may re-sort client-side via `AppSettings.inboxSort`; Home New uses this newest-first order.
    var inboxEpisodes: [InboxEpisode] {
        var items: [InboxEpisode] = []
        for feed in feeds {
            for episode in feed.episodes where !isPlayed(episode.id) && !isArchived(episode.id) {
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

    /// Write Continue-listening snapshot to the App Group for the homescreen widget.
    /// Prefers the current player episode when set; else the top continue-listening item.
    func publishWidgetSnapshot() {
        let current = playback?.currentEpisode
        let cont = continueListeningEpisodes.first
        WidgetSnapshotPublisher.publish(
            currentEpisodeId: current?.id,
            currentEpisodeTitle: current?.title,
            currentFeedTitle: current.flatMap { feed(containingEpisodeId: $0.id)?.title },
            continueEpisodeId: cont?.episode.id,
            continueEpisodeTitle: cont?.episode.title,
            continueFeedTitle: cont?.feedTitle
        )
        // Keep Apple Watch Continue-listening in sync (WC applicationContext).
        WatchCompanionBridge.shared.pushCurrentSnapshot()
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



    // MARK: - Archive / restore

    func isArchived(_ episodeId: String) -> Bool {
        archivedAtById[episodeId] != nil
    }

    func archive(_ episodeId: String) {
        guard !isArchived(episodeId) else { return }
        archivedAtById[episodeId] = Int64(Date().timeIntervalSince1970 * 1000)
    }

    func restore(_ episodeId: String) {
        archivedAtById.removeValue(forKey: episodeId)
    }

    /// Un-archive every id in `archived.json` (same as per-row Restore).
    /// Clears the whole `archivedAtById` side map; does not mark unplayed,
    /// delete downloads, or clear the queue. Persists via didSet.
    func restoreAllArchived() {
        guard !archivedAtById.isEmpty else { return }
        archivedAtById = [:]
    }

    func toggleArchived(_ episodeId: String) {
        if isArchived(episodeId) {
            restore(episodeId)
        } else {
            archive(episodeId)
        }
    }

    /// Archive every episode currently in the Inbox list (bulk).
    func archiveAllInbox() {
        let ids = inboxEpisodes.map(\.episode.id)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
    }

    /// Mark every episode currently in the Inbox list as played (bulk).
    /// Snapshots Inbox ids first, then calls `markPlayed` per id so auto-delete-after-playing
    /// and queue removal side effects still apply. Does not touch All Episodes / History lists.
    func markAllInboxPlayed() {
        let ids = inboxEpisodes.map(\.episode.id)
        for id in ids {
            markPlayed(id)
        }
    }

    /// Mark every unplayed, non-archived episode in one feed as played (bulk).
    /// Snapshots eligible ids first, then calls `markPlayed` per id so auto-delete-after-playing
    /// and queue removal side effects still apply. Feed-scoped only; does not archive.
    func markAllPlayed(inFeedId feedId: String) {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return }
        let ids = feed.episodes
            .filter { !isPlayed($0.id) && !isArchived($0.id) }
            .map(\.id)
        for id in ids {
            markPlayed(id)
        }
    }

    /// Archived episodes across feeds, newest archived first.
    var archivedEpisodes: [ArchivedEpisode] {
        var items: [ArchivedEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                guard let at = archivedAtById[episode.id] else { continue }
                items.append(
                    ArchivedEpisode(
                        episode: episode,
                        feedTitle: feed.title,
                        archivedAtEpochMs: at
                    )
                )
            }
        }
        let knownIds = Set(items.map(\.id))
        for episode in queue where !knownIds.contains(episode.id) {
            guard let at = archivedAtById[episode.id] else { continue }
            let title = feed(containingEpisodeId: episode.id)?.title ?? ""
            items.append(
                ArchivedEpisode(
                    episode: episode,
                    feedTitle: title,
                    archivedAtEpochMs: at
                )
            )
        }
        items.sort { lhs, rhs in
            if lhs.archivedAtEpochMs != rhs.archivedAtEpochMs {
                return lhs.archivedAtEpochMs > rhs.archivedAtEpochMs
            }
            return lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title) == .orderedAscending
        }
        return items
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

    /// Remove every starred id from `favorites.json` (same as per-row Unfavorite).
    /// Clears the whole `favoriteAtById` side map; does not delete downloads, archive,
    /// mark played, or clear the queue. No auto-delete on unfavorite. Persists via didSet.
    func clearFavorites() {
        guard !favoriteAtById.isEmpty else { return }
        favoriteAtById = [:]
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

    /// Remove every history-listed episode's playback state (same as per-row Remove).
    /// Drops the whole `playbackStates` entry (progress + `isPlayed` + `lastPlayedAt`) —
    /// matching `removeFromHistory`. Does not unsubscribe feeds, delete downloads,
    /// clear the queue, or unstar favorites. Persists via `playbackStates` didSet.
    func clearHistory() {
        let ids = Set(historyEpisodes.map(\.id))
        guard !ids.isEmpty else { return }
        var next = playbackStates
        for id in ids {
            next.removeValue(forKey: id)
            pendingAutoDeleteIds.remove(id)
        }
        playbackStates = next
    }

    // MARK: - Statistics (from playback.json)

    /// Totals + per-feed top list derived from saved playback state (honest approximation).
    var listeningStatistics: ListeningStatistics {
        var played = 0
        var inProgress = 0
        var totalSeconds: Double = 0
        var perFeed: [UUID: (title: String, played: Int, inProgress: Int, seconds: Double)] = [:]

        for feed in feeds {
            var feedPlayed = 0
            var feedInProgress = 0
            var feedSeconds: Double = 0
            for episode in feed.episodes {
                let state = playbackState(for: episode.id)
                guard ListeningTimeEstimate.hasMeaningfulData(state) else { continue }
                let secs = ListeningTimeEstimate.seconds(for: state)
                if state.isPlayed {
                    played += 1
                    feedPlayed += 1
                } else {
                    inProgress += 1
                    feedInProgress += 1
                }
                totalSeconds += secs
                feedSeconds += secs
            }
            if feedPlayed > 0 || feedInProgress > 0 {
                perFeed[feed.id] = (feed.title, feedPlayed, feedInProgress, feedSeconds)
            }
        }

        // Queue-only episodes with playback state (same as History).
        let knownEpisodeIds = Set(feeds.flatMap { $0.episodes.map(\.id) })
        for episode in queue where !knownEpisodeIds.contains(episode.id) {
            let state = playbackState(for: episode.id)
            guard ListeningTimeEstimate.hasMeaningfulData(state) else { continue }
            let secs = ListeningTimeEstimate.seconds(for: state)
            if state.isPlayed {
                played += 1
            } else {
                inProgress += 1
            }
            totalSeconds += secs
            if let feed = feed(containingEpisodeId: episode.id) {
                var entry = perFeed[feed.id] ?? (feed.title, 0, 0, 0)
                if state.isPlayed {
                    entry.played += 1
                } else {
                    entry.inProgress += 1
                }
                entry.seconds += secs
                perFeed[feed.id] = entry
            }
        }

        let top = perFeed.map { (id, v) in
            FeedListeningStats(
                id: id,
                feedTitle: v.title,
                playedEpisodeCount: v.played,
                inProgressEpisodeCount: v.inProgress,
                approximateListenedSeconds: v.seconds
            )
        }
        .sorted { lhs, rhs in
            if lhs.approximateListenedSeconds != rhs.approximateListenedSeconds {
                return lhs.approximateListenedSeconds > rhs.approximateListenedSeconds
            }
            if lhs.playedEpisodeCount != rhs.playedEpisodeCount {
                return lhs.playedEpisodeCount > rhs.playedEpisodeCount
            }
            return lhs.feedTitle.localizedCaseInsensitiveCompare(rhs.feedTitle) == .orderedAscending
        }

        return ListeningStatistics(
            playedEpisodeCount: played,
            inProgressEpisodeCount: inProgress,
            approximateListenedSeconds: totalSeconds,
            topPodcasts: top
        )
    }

    // MARK: - Echo (Year in Review)

    /// Calendar-year listening summary from `playback.json` + `favorites.json`.
    /// Uses the device calendar (Europe/Berlin when the device is set that way).
    /// Played episodes counted when `isPlayed` and `lastPlayedAt` (else `updatedAt`) falls in `year`.
    func echoYearSummary(
        for year: Int? = nil,
        calendar: Calendar = .current
    ) -> EchoYearSummary {
        let resolvedYear = year ?? calendar.component(.year, from: Date())
        guard
            let start = calendar.date(from: DateComponents(year: resolvedYear, month: 1, day: 1)),
            let end = calendar.date(from: DateComponents(year: resolvedYear + 1, month: 1, day: 1))
        else {
            return .empty(year: resolvedYear)
        }
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(end.timeIntervalSince1970 * 1000)

        func inYear(_ epochMs: Int64) -> Bool {
            epochMs >= startMs && epochMs < endMs
        }

        var played = 0
        var totalSeconds: Double = 0
        var perFeed: [UUID: (title: String, played: Int, seconds: Double)] = [:]

        func consider(episodeId: String, feedId: UUID?, feedTitle: String) {
            let state = playbackState(for: episodeId)
            guard state.isPlayed else { return }
            let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
            guard inYear(lastPlayed) else { return }
            played += 1
            let secs = ListeningTimeEstimate.seconds(for: state)
            totalSeconds += secs
            guard let feedId else { return }
            var entry = perFeed[feedId] ?? (feedTitle, 0, 0)
            entry.played += 1
            entry.seconds += secs
            perFeed[feedId] = entry
        }

        for feed in feeds {
            for episode in feed.episodes {
                consider(episodeId: episode.id, feedId: feed.id, feedTitle: feed.title)
            }
        }
        let knownEpisodeIds = Set(feeds.flatMap { $0.episodes.map(\.id) })
        for episode in queue where !knownEpisodeIds.contains(episode.id) {
            let feed = feed(containingEpisodeId: episode.id)
            consider(
                episodeId: episode.id,
                feedId: feed?.id,
                feedTitle: feed?.title ?? ""
            )
        }

        let top = perFeed.map { (id, v) in
            EchoFeedStats(
                id: id,
                feedTitle: v.title,
                playedEpisodeCount: v.played,
                approximateListenedSeconds: v.seconds
            )
        }
        .sorted { lhs, rhs in
            if lhs.approximateListenedSeconds != rhs.approximateListenedSeconds {
                return lhs.approximateListenedSeconds > rhs.approximateListenedSeconds
            }
            if lhs.playedEpisodeCount != rhs.playedEpisodeCount {
                return lhs.playedEpisodeCount > rhs.playedEpisodeCount
            }
            return lhs.feedTitle.localizedCaseInsensitiveCompare(rhs.feedTitle) == .orderedAscending
        }

        var favoritesThisYear = 0
        for (_, favoritedAt) in favoriteAtById {
            if inYear(favoritedAt) {
                favoritesThisYear += 1
            }
        }

        return EchoYearSummary(
            year: resolvedYear,
            playedEpisodeCount: played,
            approximateListenedSeconds: totalSeconds,
            topPodcasts: Array(top.prefix(10)),
            favoritesCountThisYear: favoritesThisYear,
            favoritesTotalCount: favoriteAtById.count
        )
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
            if LocalFolderFeed.isLocalFolderFeed(feed) {
                let existingIds = Set(feed.episodes.map(\.id))
                do {
                    let updated = try rescanLocalFolderFeed(feed)
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
                } catch {
                    lastError = error.localizedDescription
                }
                continue
            }
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
        await NewEpisodeActionCoordinator.apply(
            newBatches,
            store: self,
            downloads: downloads,
            settings: settings
        )
        await AutoDownloadCoordinator.enqueueAfterRefresh(
            store: self,
            downloads: downloads,
            settings: settings
        )
    }

    // MARK: - Library search (local only)

    /// Matching subscriptions by feed title or feed descriptionText (case-insensitive; no author fields on PodcastFeed).
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
            for episode in feed.episodes where Self.matches(episode.title, query: q)
                || Self.matches(episode.descriptionText, query: q) {
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

    // MARK: - Local folder feeds (beta)

    /// Subscribe to a user-picked folder: persist security-scoped bookmark + synthetic feed.
    /// Call while the picker URL still has security-scoped access (`fileImporter`).
    func subscribeLocalFolder(folderURL: URL) throws {
        lastError = nil
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LocalFolderFeedError.notAFolder
        }
        let feedId = UUID()
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        try LocalFolderBookmarkStore.saveBookmark(forFolderURL: folderURL, feedId: feedId)
        let feed: PodcastFeed
        do {
            // Prefer tracked access for later playback; fall back to picker URL for the initial scan.
            let folder = (try? LocalFolderAccess.beginAccess(feedId: feedId)) ?? folderURL
            feed = try LocalFolderScanner.buildFeed(feedId: feedId, folderURL: folder)
        } catch {
            LocalFolderBookmarkStore.release(feedId: feedId)
            throw error
        }
        feeds.append(feed)
    }

    /// Re-scan one local folder feed (manual Refresh swipe).
    func refreshLocalFolderFeed(_ feed: PodcastFeed) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        let existingIds = Set(feed.episodes.map(\.id))
        do {
            let updated = try rescanLocalFolderFeed(feed)
            let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
            if !newcomers.isEmpty {
                let batches = [
                    NewEpisodeBatch(
                        feedTitle: updated.title,
                        feedId: updated.id,
                        feedUrl: updated.feedUrl,
                        episodes: newcomers
                    )
                ]
                await NewEpisodeNotificationCoordinator.handleNewEpisodes(
                    batches,
                    settings: settings,
                    store: self
                )
                await NewEpisodeActionCoordinator.apply(
                    batches,
                    store: self,
                    downloads: downloads,
                    settings: settings
                )
            }
            await AutoDownloadCoordinator.enqueueAfterRefresh(
                store: self,
                downloads: downloads,
                settings: settings
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Best-effort re-scan of all local folder feeds (launch / backup import) so file:// paths stay current.
    private func rescanLocalFolderFeedsBestEffort() {
        let locals = feeds.filter { LocalFolderFeed.isLocalFolderFeed($0) }
        for feed in locals {
            _ = try? rescanLocalFolderFeed(feed)
        }
    }

    /// Re-scan folder from bookmark; preserves feed id + title; updates episode list.
    @discardableResult
    func rescanLocalFolderFeed(_ feed: PodcastFeed) throws -> PodcastFeed {
        let folder = try LocalFolderAccess.beginAccess(feedId: feed.id)
        var updated = try LocalFolderScanner.buildFeed(
            feedId: feed.id,
            folderURL: folder,
            existingTitle: feed.title
        )
        if !feed.title.isEmpty {
            updated.title = feed.title
        }
        if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
            feeds[index] = updated
        } else {
            feeds.append(updated)
        }
        return updated
    }

    // MARK: - OPML import / export

    func exportOpmlXML() -> String {
        OpmlWriter.writeDocument(feeds: feeds)
    }

    func exportOpmlTemporaryFile() throws -> URL {
        try OpmlWriter.writeTemporaryFile(feeds: feeds)
    }

    // MARK: - HTML export (subscriptions)

    func exportSubscriptionsHTML(includeEpisodeCount: Bool = true) -> String {
        HtmlExportWriter.writeDocument(feeds: feeds, includeEpisodeCount: includeEpisodeCount)
    }

    func exportSubscriptionsHTMLTemporaryFile(includeEpisodeCount: Bool = true) throws -> URL {
        try HtmlExportWriter.writeTemporaryFile(feeds: feeds, includeEpisodeCount: includeEpisodeCount)
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

