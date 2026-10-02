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
    /// Episode id → user bookmarks (`bookmarks.json`). Local-only wall-clock positions; not gpodder.
    @Published var bookmarksByEpisodeId: [String: [EpisodeBookmark]] = [:] {
        didSet { PodcastPersistence.saveBookmarks(bookmarksByEpisodeId) }
    }
    /// Feed id → tag names (`feed-tags.json` side map). Tags exist only while assigned.
    @Published var tagsByFeedId: [UUID: [String]] = [:] {
        didSet { PodcastPersistence.saveFeedTags(tagsByFeedId) }
    }
    @Published var isLoading = false
    /// Feeds finished (success or failure) during the in-flight `refreshAllFeeds()`.
    /// Honest completion count only — not a byte/percent estimate. Zero when idle.
    @Published var refreshCompletedCount = 0
    /// Feeds that will run in the in-flight `refreshAllFeeds()` (non-empty URL + Keep updated participates).
    /// Zero when idle or for non-bulk `isLoading` work (subscribe / single-feed refresh).
    @Published var refreshTotalCount = 0
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
        bookmarksByEpisodeId = PodcastPersistence.loadBookmarks()
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
        bookmarksByEpisodeId = PodcastPersistence.loadBookmarks()
        tagsByFeedId = PodcastPersistence.loadFeedTags()
        LocalFolderBookmarkStore.reloadFromPersistence()
        pendingAutoDeleteIds = []
        lastError = nil
        rescanLocalFolderFeedsBestEffort()
        trimHistoryToSizeLimitIfNeeded()
        publishWidgetSnapshot()
    }

    func subscribe(feedUrl: String, credentials: FeedHttpBasicCredentials? = nil) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await subscribeQuietly(
                feedUrl: feedUrl,
                credentials: credentials,
                persistCredentials: credentials?.isUsable == true
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Remove a subscription.
    /// Clears the feed from the list, per-feed settings, tags, queue items from this feed,
    /// and favorites / archive / bookmarks / playback-history entries for its episodes.
    /// Also deletes per-feed HTTP Basic credentials from the Keychain (never in JSON).
    /// Local-folder feeds also release the security-scoped bookmark.
    /// Does **not** delete downloaded episode files by itself — UI may call
    /// `DownloadService.deleteDownloads(forFeed:)` **before** this when the user chooses
    /// Unsubscribe and delete downloads (feed-scoped offline files only).
    func unsubscribe(_ feed: PodcastFeed) {
        if LocalFolderFeed.isLocalFolderFeed(feed) {
            LocalFolderBookmarkStore.release(feedId: feed.id)
        }
        FeedHttpBasicAuthKeychain.delete(for: feed.id)
        feeds.removeAll { $0.id == feed.id }
        feedSettingsById.removeValue(forKey: feed.id)
        tagsByFeedId.removeValue(forKey: feed.id)
        let ids = Set(feed.episodes.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        for id in ids {
            playbackStates.removeValue(forKey: id)
            favoriteAtById.removeValue(forKey: id)
            archivedAtById.removeValue(forKey: id)
            bookmarksByEpisodeId.removeValue(forKey: id)
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
        var newBatches: [NewEpisodeBatch] = []
        if wasSubscribed, let updated = feeds.first(where: { $0.feedUrl == feed.feedUrl }) {
            let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
            if !newcomers.isEmpty {
                newBatches = [
                    NewEpisodeBatch(
                        feedTitle: updated.title,
                        feedId: updated.id,
                        feedUrl: updated.feedUrl,
                        episodes: newcomers
                    )
                ]
                await NewEpisodeNotificationCoordinator.handleNewEpisodes(
                    newBatches,
                    settings: settings,
                    store: self
                )
                await NewEpisodeActionCoordinator.apply(
                    newBatches,
                    store: self,
                    downloads: downloads,
                    settings: settings
                )
            }
        }
        await AutoDownloadCoordinator.enqueueAfterRefresh(
            store: self,
            downloads: downloads,
            settings: settings,
            newBatches: newBatches
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

    /// Drop one episode from the queue. Persists via `queue` `didSet`.
    /// Does not stop playback, change progress, mark played, or delete downloads — queue entry only.
    /// UI callers (Queue swipe Remove, Full Player Remove from queue) must confirm first.
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
    /// Does not stop playback, change progress, mark played, or delete downloads — only clears queue entries.
    /// Callers must confirm first (Queue tab `confirmationDialog`); safe while queue lock is on (reorder-only).
    func clearQueue() {
        queue = []
    }

    /// Randomly reorder the **full** persisted queue (Fisher–Yates via `Array.shuffle()`).
    /// Persists via `queue` `didSet` (same path as `moveQueue`). No-op when fewer than 2 items.
    /// Does **not** change `PlaybackService.currentEpisode` identity, seek, or stop playback —
    /// the currently playing episode (if any) **moves with its episode id** to a new list index
    /// (it is not pinned at the same index). Continuous next still uses `nextQueueEpisode(after:)`
    /// by id, so auto-next becomes whatever follows that id after the shuffle.
    /// Callers must gate on queue unlock (reorder-only lock, same as Edit/`onMove`) and confirm first.
    func shuffleQueue() {
        guard queue.count >= 2 else { return }
        var shuffled = queue
        shuffled.shuffle()
        queue = shuffled
    }

    /// Shuffle the **full** persisted queue, then move the currently playing episode to **index 0**
    /// when it is in the queue. Composes `shuffleQueue()` + `moveQueueItemToTop(_:)`.
    /// If `currentEpisode` is `nil` or not queued, behaves like plain `shuffleQueue`
    /// (`moveQueueItemToTop` no-ops when not queued / already first).
    /// Persists via `queue` `didSet` (same path as `moveQueue` / `shuffleQueue`). No-op when fewer than 2 items.
    /// Does **not** change `PlaybackService.currentEpisode` identity, seek, or stop playback.
    /// Callers must gate on queue unlock (reorder-only lock, same as Shuffle) and confirm first.
    func shuffleQueueKeepingPlayingFirst(currentEpisode: PodcastEpisode?) {
        shuffleQueue()
        if let currentEpisode {
            moveQueueItemToTop(currentEpisode)
        }
    }

    /// Reverse the **full** persisted queue order (first ↔ last).
    /// Persists via `queue` `didSet` (same path as `moveQueue` / `shuffleQueue`). No-op when fewer than 2 items.
    /// Does **not** change `PlaybackService.currentEpisode` identity, seek, or stop playback —
    /// the currently playing episode (if any) **moves with its episode id** to the mirrored list index
    /// (it is not pinned at the same index). Continuous next still uses `nextQueueEpisode(after:)`
    /// by id, so auto-next becomes whatever follows that id after the reverse.
    /// Callers must gate on queue unlock (reorder-only lock, same as Edit/`onMove` / Shuffle) and confirm first.
    func reverseQueue() {
        guard queue.count >= 2 else { return }
        queue = Array(queue.reversed())
    }

    /// Sort the **full** persisted queue by episode `pubDateEpochMs` (newest or oldest first).
    /// Persists via `queue` `didSet` (same path as `moveQueue` / `shuffleQueue` / `reverseQueue`).
    /// No-op when fewer than 2 items. Episodes **missing** `pubDateEpochMs` sort **last** in both modes;
    /// equal dates (or both missing) break ties by stable episode `id`.
    /// Does **not** change `PlaybackService.currentEpisode` identity, seek, or stop playback —
    /// the currently playing episode (if any) **moves with its episode id** to its new list index
    /// (it is not pinned at the same index). Continuous next still uses `nextQueueEpisode(after:)`
    /// by id, so auto-next becomes whatever follows that id after the sort.
    /// One-shot reorder of `queue.json` — **not** a persistent filter preference (unlike Inbox/`inboxSort`).
    /// Callers must gate on queue unlock (reorder-only lock, same as Shuffle/Reverse) and confirm first.
    func sortQueueByPublishDate(newestFirst: Bool) {
        guard queue.count >= 2 else { return }
        queue = queue.sorted { lhs, rhs in
            switch (lhs.pubDateEpochMs, rhs.pubDateEpochMs) {
            case let (l?, r?):
                if l != r {
                    return newestFirst ? (l > r) : (l < r)
                }
                return lhs.id < rhs.id
            case (_?, nil):
                return true // dated before missing
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.id < rhs.id
            }
        }
    }

    /// Sort the **full** persisted queue by known episode duration (shortest or longest first).
    /// Duration source honesty (same known-duration path as remaining-time helpers, without live
    /// player): prefer feed `itunes:duration` / media via `PodcastEpisode.hasKnownDuration` /
    /// `durationSeconds`; else saved `EpisodePlaybackState.durationSeconds` when finite & > 0.
    /// Never invents a length. Episodes with **unknown** duration sort **last** in both modes;
    /// equal durations (or both unknown) break ties by stable episode `id`.
    /// Persists via `queue` `didSet` (same path as `moveQueue` / `shuffleQueue` / `reverseQueue` /
    /// `sortQueueByPublishDate`). No-op when fewer than 2 items.
    /// Does **not** change `PlaybackService.currentEpisode` identity, seek, or stop playback —
    /// the currently playing episode (if any) **moves with its episode id** to its new list index
    /// (it is not pinned at the same index). Continuous next still uses `nextQueueEpisode(after:)`
    /// by id, so auto-next becomes whatever follows that id after the sort.
    /// One-shot reorder of `queue.json` — **not** a persistent filter preference (unlike Inbox/`inboxSort`).
    /// Callers must gate on queue unlock (reorder-only lock, same as Shuffle/Reverse/Sort by date) and confirm first.
    func sortQueueByDuration(shortestFirst: Bool) {
        guard queue.count >= 2 else { return }
        queue = queue.sorted { lhs, rhs in
            switch (knownDurationSecondsForQueueSort(lhs), knownDurationSecondsForQueueSort(rhs)) {
            case let (l?, r?):
                if l != r {
                    return shortestFirst ? (l < r) : (l > r)
                }
                return lhs.id < rhs.id
            case (_?, nil):
                return true // known before unknown
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.id < rhs.id
            }
        }
    }

    /// Feed duration when known; else saved playback duration. Never invents a length.
    /// Matches remaining-time known-duration path except live player (store sort has no PlaybackService).
    private func knownDurationSecondsForQueueSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: playbackState(for: episode.id).durationSeconds
        )
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
        trimHistoryToSizeLimitIfNeeded()
        publishWidgetSnapshot()
    }

    /// Mark played. Position: when Settings **Reset position when marked played** is on (default),
    /// clears `positionSeconds` to 0 for a clean resume-from-start later; when off, keeps the saved position
    /// (Mark unplayed can resume). Applies to manual toggle, Inbox/Feed mark-all, smart-mark, and natural end.
    /// When auto-delete-after-playing is on, removes the local download file (keeps the episode row).
    /// Counts a successful mark-played for the optional App Store rating prompt when newly played.
    func markPlayed(_ episodeId: String, removeFromQueue: Bool = true) {
        let wasPlayed = isPlayed(episodeId)
        var state = playbackState(for: episodeId)
        state.isPlayed = true
        let resetPosition = settings?.resetPositionWhenMarkedPlayed ?? true
        if resetPosition {
            state.positionSeconds = 0
        }
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
        trimHistoryToSizeLimitIfNeeded()
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
        trimHistoryToSizeLimitIfNeeded()
    }

    /// Next Queue item after `episodeId` for continuous playback (**Queue order only**).
    /// If `episodeId` is in the queue, returns the following entry (or `nil` at the tail).
    /// If not queued, returns the head of the queue (same honesty as Play Next when current is not queued).
    /// Does **not** walk the feed/podcast episode list — never invents “next episode of this show.”
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
        if let feed = feeds.first(where: { feed in
            feed.episodes.contains { $0.id == episodeId }
        }) {
            return feed
        }
        // Synthetic channel podcast:trailer playback ids: podcast-trailer:<feedUUID>:<mediaURL>
        // so Now Playing can resolve artwork / podcast title without adding trailer to episodes[].
        if episodeId.hasPrefix("podcast-trailer:") {
            let parts = episodeId.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            // ["podcast-trailer", "<uuid>", "<url…>"]
            if parts.count >= 2, let feedId = UUID(uuidString: String(parts[1])) {
                return feeds.first { $0.id == feedId }
            }
        }
        return nil
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

    /// Owning subscription for an episode id (first match in `feeds`).
    func feed(containingEpisodeId episodeId: String) -> PodcastFeed? {
        feeds.first { feed in
            feed.episodes.contains { $0.id == episodeId }
        }
    }

    /// HTTP Basic credentials from Keychain for an already-subscribed feed URL (if any).
    func httpBasicCredentials(forFeedUrl feedUrl: String) -> FeedHttpBasicCredentials? {
        guard let feed = FeedURLNormalization.subscribedFeed(matching: feedUrl, in: feeds) else {
            return nil
        }
        return FeedHttpBasicAuthKeychain.load(for: feed.id)
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

    /// Resolves global + per-feed Use global / Always / Never for auto-delete after play.
    /// Orphan episodes (no owning feed) follow the global toggle only.
    private func shouldAutoDeleteAfterPlaying(episodeId: String) -> Bool {
        let global = settings?.autoDeleteAfterPlaying == true
        guard let feed = feed(containingEpisodeId: episodeId) else {
            return global
        }
        return feedSettings(for: feed.id).allowsAutoDeleteAfterPlaying(globalEnabled: global)
    }

    private func enqueueAutoDeleteAfterPlaying(_ episodeId: String) {
        guard shouldAutoDeleteAfterPlaying(episodeId: episodeId) else {
            pendingAutoDeleteIds.remove(episodeId)
            return
        }
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
        guard shouldAutoDeleteAfterPlaying(episodeId: episodeId) else { return }
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

    /// Per-feed unplayed counts (`!isPlayed && !isArchived`), one pass over stored `feed.episodes`.
    /// Same definition as Inbox / All Episodes Unplayed / Feed detail Unplayed.
    /// Counts the full stored feed catalog — **not** the All Episodes newest-500 soft cap.
    /// Omits feeds with zero unplayed (callers treat missing as 0).
    /// Prefer `unplayedRemainingByFeedId()` when Subscriptions also needs per-feed remaining
    /// (same pass returns count + remaining).
    func unplayedCountsByFeedId() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(feeds.count)
        for feed in feeds {
            var n = 0
            for episode in feed.episodes where !isPlayed(episode.id) && !isArchived(episode.id) {
                n += 1
            }
            if n > 0 {
                counts[feed.id] = n
            }
        }
        return counts
    }

    /// Per-feed unplayed remaining (`!isPlayed && !isArchived`), **one pass** over stored
    /// `feed.episodes` — same definition / catalog honesty as `unplayedCountsByFeedId` / Inbox
    /// (full stored feed catalog; **not** All Episodes newest-500 soft cap; RSS window inherent).
    /// Remaining = wall-clock sum of `max(0, duration − position)` when duration known; unknown
    /// durations skipped (`unknownCount`); live `PlaybackService` position/duration when that
    /// episode is current (if `playback` is wired). **Played** (not current) → 0 (defensive —
    /// set is already unplayed). Omits feeds with zero unplayed (callers treat missing as 0 /
    /// hide remaining).
    func unplayedRemainingByFeedId() -> [UUID: FeedUnplayedRemainingSummary] {
        var result: [UUID: FeedUnplayedRemainingSummary] = [:]
        result.reserveCapacity(feeds.count)
        let currentId = playback?.currentEpisode?.id
        let liveDur = playback?.durationSeconds ?? 0
        let livePos = playback?.positionSeconds ?? 0
        for feed in feeds {
            let episodes = feed.episodes.filter { !isPlayed($0.id) && !isArchived($0.id) }
            guard !episodes.isEmpty else { continue }
            let summary = EpisodeRemainingTime.summarize(
                episodes: episodes,
                currentEpisodeId: currentId,
                liveDurationSeconds: liveDur,
                livePositionSeconds: livePos,
                isPlayed: { isPlayed($0) },
                savedDurationSeconds: { playbackState(for: $0).durationSeconds },
                savedPositionSeconds: { positionSeconds(for: $0) }
            )
            result[feed.id] = FeedUnplayedRemainingSummary(
                unplayedCount: summary.episodeCount,
                remainingSeconds: summary.remainingSeconds,
                knownCount: summary.knownCount,
                unknownCount: summary.unknownCount
            )
        }
        return result
    }

    // MARK: - All Episodes (catalog)

    /// Soft cap for All Episodes (newest by pubDate). Keeps List honest without lazy paging.
    /// AllEpisodesView may re-sort via `allEpisodesSort`; Oldest only reorders within this cap.
    static let allEpisodesSoftLimit = 500

    /// All episodes across subscriptions, newest `pubDateEpochMs` first (soft-capped).
    /// Distinct from Inbox (unplayed only): played / in-progress are included.
    /// Store order stays newest-first; AllEpisodesView applies `allEpisodesSort` client-side.
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

    /// Append every soft-capped All Episodes item that is not already queued (bulk).
    /// Uses store `allEpisodes` order (**newest-first** by `pubDateEpochMs` within the
    /// newest-**500** soft cap — same catalog as Library → Episodes). Does **not** follow
    /// UI `allEpisodesSort`, chip filter (`allEpisodesFilter`), or searchable filter.
    /// **Soft-cap honesty:** never enqueues beyond the newest-500 set.
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (All Episodes toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllEpisodes() -> Int {
        let candidates = allEpisodes.map(\.episode).filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    // MARK: - Home sections

    /// In-progress (not played) episodes with meaningful progress, newest `lastPlayedAt` first.
    var continueListeningEpisodes: [HistoryEpisode] {
        historyEpisodes.filter { item in
            let state = playbackState(for: item.episode.id)
            return !state.isPlayed && state.positionSeconds > 1
        }
    }

    /// Write Continue-listening snapshot to the App Group for the homescreen widget / Watch.
    /// Prefers the current player episode when set; else the top continue-listening item.
    /// Position + duration come from the same publish moment as title/feed (may be stale;
    /// wall-clock remaining = max(0, duration − position) when duration known).
    func publishWidgetSnapshot() {
        let current = playback?.currentEpisode
        let cont = continueListeningEpisodes.first

        var currentPosition: Double? = nil
        var currentDuration: Double? = nil
        if let current {
            if let playback, playback.currentEpisode?.id == current.id {
                let livePos = playback.positionSeconds
                currentPosition = livePos.isFinite ? max(0, livePos) : 0
                let liveDur = playback.durationSeconds
                if liveDur.isFinite, liveDur > 0 {
                    currentDuration = liveDur
                }
            }
            if currentDuration == nil {
                currentDuration = knownDurationSeconds(for: current)
            }
            if currentPosition == nil {
                currentPosition = max(0, positionSeconds(for: current.id))
            }
        }

        var continuePosition: Double? = nil
        var continueDuration: Double? = nil
        if let cont {
            continuePosition = max(0, positionSeconds(for: cont.episode.id))
            continueDuration = knownDurationSeconds(for: cont.episode)
            // Live player wins when the continue top item is also current.
            if let playback, playback.currentEpisode?.id == cont.episode.id {
                let livePos = playback.positionSeconds
                continuePosition = livePos.isFinite ? max(0, livePos) : continuePosition
                let liveDur = playback.durationSeconds
                if liveDur.isFinite, liveDur > 0 {
                    continueDuration = liveDur
                }
            }
        }

        WidgetSnapshotPublisher.publish(
            currentEpisodeId: current?.id,
            currentEpisodeTitle: current?.title,
            currentFeedTitle: current.flatMap { feed(containingEpisodeId: $0.id)?.title },
            currentPositionSeconds: currentPosition,
            currentDurationSeconds: currentDuration,
            continueEpisodeId: cont?.episode.id,
            continueEpisodeTitle: cont?.episode.title,
            continueFeedTitle: cont?.feedTitle,
            continuePositionSeconds: continuePosition,
            continueDurationSeconds: continueDuration
        )
        // Keep Apple Watch Continue-listening in sync (WC applicationContext).
        WatchCompanionBridge.shared.pushCurrentSnapshot()
    }

    /// Prefer live player duration when this episode is current; else feed `itunes:duration` /
    /// media; else saved playback duration. Never invents a length. Used by widget snapshot.
    private func knownDurationSeconds(for episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            currentEpisodeId: playback?.currentEpisode?.id,
            liveDurationSeconds: playback?.durationSeconds ?? 0,
            savedDurationSeconds: playbackState(for: episode.id).durationSeconds
        )
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

    /// Append every archived episode that is not already queued (bulk).
    /// Uses store `archivedEpisodes` order (**newest-first** by `archivedAtEpochMs` —
    /// same catalog as Restore all). Does **not** follow UI `archivedSort`, podcast chip, or searchable filter.
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Does **not** restore / unarchive (archive side map unchanged).
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (Archived toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllArchived() -> Int {
        let candidates = archivedEpisodes.map(\.episode).filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
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

    /// Append every Inbox episode that is not already queued (bulk).
    /// Uses store `inboxEpisodes` order (**newest-first** by `pubDateEpochMs` — same catalog as
    /// `archiveAllInbox` / `markAllInboxPlayed`). Does **not** follow UI `inboxSort`.
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (Inbox toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllInbox() -> Int {
        let candidates = inboxEpisodes.map(\.episode).filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
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

    /// Append every episode from one feed that is not already queued (bulk).
    /// Uses the **full** stored feed episode catalog (`feed.episodes`), sorted **newest-first**
    /// by `pubDateEpochMs` (missing dates last; title tiebreak — same spirit as Feed Download all).
    /// Does **not** follow UI `feedEpisodeSort`, chip filter (`feedEpisodeFilter`), or searchable filter
    /// — same full-feed honesty as Mark all as played / Download all.
    /// Includes played and archived episodes (unlike Download all / Mark all eligibility).
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (Feed detail toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllFromFeed(_ feed: PodcastFeed) -> Int {
        let sorted = feed.episodes.sorted { lhs, rhs in
            let l = lhs.pubDateEpochMs ?? Int64.min
            let r = rhs.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let candidates = sorted.filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
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


    // MARK: - Episode bookmarks (local-only)

    /// Newest-first bookmarks for an episode (empty when none).
    func bookmarks(for episodeId: String) -> [EpisodeBookmark] {
        EpisodeBookmarkStore.sortedNewestFirst(bookmarksByEpisodeId[episodeId] ?? [])
    }

    /// Number of bookmarks for an episode.
    func bookmarkCount(for episodeId: String) -> Int {
        bookmarksByEpisodeId[episodeId]?.count ?? 0
    }

    /// Whether the episode is at the per-episode bookmark cap.
    func isBookmarkCapReached(for episodeId: String) -> Bool {
        bookmarkCount(for: episodeId) >= EpisodeBookmarkStore.maxPerEpisode
    }

    /// Add a bookmark at `positionSeconds` with optional note.
    /// Returns `false` when the per-episode cap (`EpisodeBookmarkStore.maxPerEpisode`) is reached.
    @discardableResult
    func addBookmark(episodeId: String, positionSeconds: Double, note: String = "") -> Bool {
        guard positionSeconds.isFinite, positionSeconds >= 0 else { return false }
        var list = bookmarksByEpisodeId[episodeId] ?? []
        guard list.count < EpisodeBookmarkStore.maxPerEpisode else { return false }
        let bookmark = EpisodeBookmark(
            positionSeconds: positionSeconds,
            note: EpisodeBookmarkStore.trimNote(note)
        )
        list.append(bookmark)
        var map = bookmarksByEpisodeId
        map[episodeId] = list
        bookmarksByEpisodeId = map
        return true
    }

    /// Remove one bookmark by id. No-op when missing.
    func removeBookmark(episodeId: String, bookmarkId: UUID) {
        guard var list = bookmarksByEpisodeId[episodeId] else { return }
        list.removeAll { $0.id == bookmarkId }
        var map = bookmarksByEpisodeId
        if list.isEmpty {
            map.removeValue(forKey: episodeId)
        } else {
            map[episodeId] = list
        }
        bookmarksByEpisodeId = map
    }

    /// Remove every bookmark for an episode.
    func clearBookmarks(for episodeId: String) {
        guard bookmarksByEpisodeId[episodeId] != nil else { return }
        var map = bookmarksByEpisodeId
        map.removeValue(forKey: episodeId)
        bookmarksByEpisodeId = map
    }

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

    /// Append every favorite episode that is not already queued (bulk).
    /// Uses store `favoriteEpisodes` order (**newest-first** by `favoritedAtEpochMs` — same catalog as
    /// Clear favorites / Home Favorites preview). Does **not** follow UI `favoritesSort`, podcast chip, or searchable filter.
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (Favorites toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllFavorites() -> Int {
        let candidates = favoriteEpisodes.map(\.episode).filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Append every completed download that is not already queued (bulk).
    /// Uses `DownloadService.downloads` **catalog order** (array as persisted — oldest completed
    /// first; new finishes append). Same full completed catalog as Delete played downloads /
    /// tab badge — **not** UI `downloadsSort`, chip filter, or searchable filter.
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Requires `downloads` wired on the store (same as auto-delete). Returns 0 if unset.
    /// Callers must confirm first (Downloads toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllDownloads() -> Int {
        guard let downloads else { return 0 }
        let candidates = downloads.downloads.map(\.episode).filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
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

    /// Append every History episode that is not already queued (bulk).
    /// Uses store `historyEpisodes` order (**newest-first** by `lastPlayedAtEpochMs` —
    /// `lastPlayedAt` else `updatedAt` — same catalog as Clear history / Home Continue).
    /// Does **not** follow UI `historySort` or searchable filter.
    /// Skips already-queued ids (no duplicates). Uses `enqueue` (append), not `playNext`.
    /// Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (History toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllHistory() -> Int {
        let candidates = historyEpisodes.map(\.episode).filter { !isInQueue($0.id) }
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Drop oldest History-listed `playbackStates` entries when over `AppSettings.historySizeLimit`.
    ///
    /// **Honesty:** History is derived from `playback.json` (no separate `history.json`).
    /// Oldest = lowest `lastPlayedAtEpochMs` else `updatedAtEpochMs` (end of newest-first `historyEpisodes`).
    /// Trim removes the whole playback entry (progress + `isPlayed` + `lastPlayedAt`) — same as
    /// `removeFromHistory` / Clear history row. Favorites, archive, downloads, and queue stay.
    /// Statistics / Echo / Continue listening may lose trimmed episodes. **Unlimited** = no-op.
    /// Call after load (settings wired), after history-growing writes, and when the Settings cap changes.
    func trimHistoryToSizeLimitIfNeeded() {
        guard let limit = settings?.historySizeLimit.entryLimit else { return }
        let catalog = historyEpisodes
        guard catalog.count > limit else { return }
        let victims = catalog.dropFirst(limit)
        var next = playbackStates
        var changed = false
        for item in victims {
            if next.removeValue(forKey: item.id) != nil {
                changed = true
            }
            pendingAutoDeleteIds.remove(item.id)
        }
        if changed {
            playbackStates = next
        }
    }

    // MARK: - Statistics (from playback.json)

    /// Totals + per-feed top list derived from saved playback state (honest approximation).
    /// Optional `range` filters by `lastPlayedAtEpochMs` else `updatedAtEpochMs` (device calendar).
    /// Also respects `AppSettings.statisticsResetAtEpochMs` baseline when > 0 (Reset statistics).
    /// Coarse episode-level stamps — not per-session listen windows; older rows may only have `updatedAt`.
    /// **Wall-clock** duration/position estimates — **not** speed-adjusted. Streaming with no saved
    /// progress is excluded. Played with unknown duration contribute 0 time.
    func listeningStatistics(
        in range: StatisticsTimeRange = .allTime,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ListeningStatistics {
        var played = 0
        var inProgress = 0
        var totalSeconds: Double = 0
        var perFeed: [UUID: (title: String, played: Int, inProgress: Int, seconds: Double)] = [:]
        let resetAt = settings?.statisticsResetAtEpochMs ?? 0

        func include(_ state: EpisodePlaybackState) -> Bool {
            guard ListeningTimeEstimate.hasMeaningfulData(state) else { return false }
            let stamp = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
            if resetAt > 0, stamp < resetAt { return false }
            return range.contains(epochMs: stamp, calendar: calendar, now: now)
        }

        for feed in feeds {
            var feedPlayed = 0
            var feedInProgress = 0
            var feedSeconds: Double = 0
            for episode in feed.episodes {
                let state = playbackState(for: episode.id)
                guard include(state) else { continue }
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
            guard include(state) else { continue }
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

    /// Listening summary from `playback.json` + `favorites.json`, filtered by `StatisticsTimeRange`.
    /// Default `.thisYear` preserves prior Year-in-Review behavior (device calendar).
    /// Played episodes counted when `isPlayed` and `lastPlayedAt` (else `updatedAt`) falls in range.
    /// Also respects `AppSettings.statisticsResetAtEpochMs` (shared with Statistics).
    /// Favorites “in range” use `favoritedAt` from `favorites.json` (also gated by reset baseline).
    /// Coarse stamps — not per-session. Wall-clock estimates — not speed-adjusted.
    func echoYearSummary(
        in range: StatisticsTimeRange = .thisYear,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> EchoYearSummary {
        let resolvedYear = calendar.component(.year, from: now)
        // Keep a year value for UI / Share when range is This year; otherwise still report current year label context.
        let bounds = range.epochRangeMs(calendar: calendar, now: now)
        let resetAt = settings?.statisticsResetAtEpochMs ?? 0

        func inRange(_ epochMs: Int64) -> Bool {
            if resetAt > 0, epochMs < resetAt { return false }
            guard let bounds else { return true }
            return epochMs >= bounds.startMs && epochMs < bounds.endMs
        }

        var played = 0
        var totalSeconds: Double = 0
        var perFeed: [UUID: (title: String, played: Int, seconds: Double)] = [:]

        func consider(episodeId: String, feedId: UUID?, feedTitle: String) {
            let state = playbackState(for: episodeId)
            guard state.isPlayed else { return }
            let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
            guard inRange(lastPlayed) else { return }
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

        var favoritesInRange = 0
        for (_, favoritedAt) in favoriteAtById {
            if inRange(favoritedAt) {
                favoritesInRange += 1
            }
        }

        return EchoYearSummary(
            year: resolvedYear,
            playedEpisodeCount: played,
            approximateListenedSeconds: totalSeconds,
            topPodcasts: Array(top.prefix(10)),
            favoritesCountThisYear: favoritesInRange,
            favoritesTotalCount: favoriteAtById.count
        )
    }

    /// Localized overlay / a11y label for bulk feed refresh. Uses real completed/total when known;
    /// falls back to indeterminate copy when `refreshTotalCount` is 0 (idle or non-bulk loading).
    var refreshProgressLabel: String {
        let total = refreshTotalCount
        if total > 0 {
            return String(
                format: String(localized: "Refreshing %lld of %lld…"),
                refreshCompletedCount,
                total
            )
        }
        return String(localized: "Refreshing feeds…")
    }

    /// Refresh every subscribed feed (Inbox pull-to-refresh + auto Keep updated). Continues on per-feed errors.
    /// Publishes honest per-feed completion counts (`refreshCompletedCount` / `refreshTotalCount`) for UI.
    func refreshAllFeeds() async {
        lastError = nil
        isLoading = true
        defer {
            isLoading = false
            refreshCompletedCount = 0
            refreshTotalCount = 0
        }
        let snapshot = feeds
        let targets = snapshot.filter {
            !$0.feedUrl.isEmpty && feedSettings(for: $0.id).participatesInBulkRefresh
        }
        refreshTotalCount = targets.count
        refreshCompletedCount = 0
        var newBatches: [NewEpisodeBatch] = []
        for feed in targets {
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
                refreshCompletedCount += 1
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
            refreshCompletedCount += 1
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
            settings: settings,
            newBatches: newBatches
        )
    }

    // MARK: - Library search (local only)

    /// Matching subscriptions by feed title, optional descriptionText, author, language, or categories (case-insensitive).
    func matchingFeeds(query: String) -> [PodcastFeed] {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }
        return feeds.filter { feed in
            Self.matches(feed.title, query: q)
                || Self.matches(feed.descriptionText, query: q)
                || Self.matches(feed.author, query: q)
                || Self.matches(feed.language, query: q)
                || Self.matches(feed.displayLanguage, query: q)
                || feed.displayCategories.contains(where: { Self.matches($0, query: q) })
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
    /// Throws `alreadySubscribed` when the same folder path is already a local-folder feed.
    @discardableResult
    func subscribeLocalFolder(folderURL: URL) throws -> PodcastFeed {
        lastError = nil
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LocalFolderFeedError.notAFolder
        }
        if LocalFolderBookmarkStore.existingFeed(matchingFolderURL: folderURL, in: feeds) != nil {
            throw LocalFolderFeedError.alreadySubscribed
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
        return feed
    }

    /// Re-scan one local folder feed (manual Refresh swipe / Feed detail Rescan).
    func refreshLocalFolderFeed(_ feed: PodcastFeed) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        let existingIds = Set(feed.episodes.map(\.id))
        do {
            let updated = try rescanLocalFolderFeed(feed)
            let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
            var newBatches: [NewEpisodeBatch] = []
            if !newcomers.isEmpty {
                newBatches = [
                    NewEpisodeBatch(
                        feedTitle: updated.title,
                        feedId: updated.id,
                        feedUrl: updated.feedUrl,
                        episodes: newcomers
                    )
                ]
                await NewEpisodeNotificationCoordinator.handleNewEpisodes(
                    newBatches,
                    settings: settings,
                    store: self
                )
                await NewEpisodeActionCoordinator.apply(
                    newBatches,
                    store: self,
                    downloads: downloads,
                    settings: settings
                )
            }
            // Local-folder feeds are skipped inside the coordinator (already on disk).
            await AutoDownloadCoordinator.enqueueAfterRefresh(
                store: self,
                downloads: downloads,
                settings: settings,
                newBatches: newBatches
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

    /// Feeds written to OPML / HTML export (excludes empty URLs and local folder feeds).
    var exportableSubscriptionCount: Int {
        feeds.filter { !$0.feedUrl.isEmpty && !LocalFolderFeed.isLocalFolderFeed($0) }.count
    }

    func exportOpmlData() throws -> Data {
        let xml = OpmlWriter.writeDocument(feeds: feeds)
        guard let data = xml.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
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
    func importOpml(data: Data, sourceFileName: String? = nil) async {
        lastError = nil
        var state = OpmlImportState(isImporting: true, sourceFileName: sourceFileName)
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
    /// Loads Keychain credentials for an existing subscription when `credentials` is nil.
    /// When `persistCredentials` is true and credentials are usable, saves them under the feed id
    /// (never into `feed-settings.json`). Passwords are never logged.
    func subscribeQuietly(
        feedUrl: String,
        credentials: FeedHttpBasicCredentials? = nil,
        persistCredentials: Bool = false
    ) async throws {
        let resolvedCreds = credentials ?? httpBasicCredentials(forFeedUrl: feedUrl)
        var feed = try await repository.fetchAndParse(feedUrl: feedUrl, credentials: resolvedCreds)
        feed.feedUrl = feedUrl
        // Stamp only on successful network fetch+parse. Failed refresh throws before this
        // and leaves any previous `lastRefreshedAtEpochMs` untouched. Local-folder feeds
        // never go through this path (Rescan is not a network refresh — leave nil / hide).
        feed.lastRefreshedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let index = feeds.firstIndex(where: { $0.feedUrl == feedUrl }) {
            feed.id = feeds[index].id // keep stable identity across refresh
            feeds[index] = feed
        } else {
            feeds.append(feed)
        }
        if persistCredentials, let credentials, credentials.isUsable {
            try? FeedHttpBasicAuthKeychain.save(
                username: credentials.trimmedUsername,
                password: credentials.password,
                for: feed.id
            )
        }
    }

}

/// Per-feed unplayed remaining from `PodcastStore.unplayedRemainingByFeedId()`.
/// `unplayedCount` matches Inbox / badge definition; remaining is wall-clock over known-duration
/// unplayed episodes only (`unknownCount` skipped with `~` in UI).
struct FeedUnplayedRemainingSummary: Equatable {
    var unplayedCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}

