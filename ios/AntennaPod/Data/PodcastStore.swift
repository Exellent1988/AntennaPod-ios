import Foundation

@MainActor
final class PodcastStore: ObservableObject {
    @Published var feeds: [PodcastFeed] = [] {
        didSet {
            // feeds.json holds every episode of every feed. Batch loops (Refresh all,
            // OPML import) change one feed at a time, so they defer and write once.
            if feedsSaveDeferralDepth > 0 {
                feedsSaveIsPending = true
            } else {
                PodcastPersistence.saveFeeds(feeds)
            }
            allEpisodesCache = nil
            inboxEpisodesCache = nil
            historyEpisodesCache = nil
            feedIndexByEpisodeIdCache = nil
        }
    }
    /// > 0 while a batch loop runs; `feeds` changes then only mark `feedsSaveIsPending`.
    private var feedsSaveDeferralDepth = 0
    private var feedsSaveIsPending = false
    @Published var queue: [PodcastEpisode] = [] {
        didSet {
            PodcastPersistence.saveQueue(queue)
            // Queue-only copies join `historyEpisodes`; clear before the widget snapshot reads it.
            historyEpisodesCache = nil
            // Queue changes can affect Continue listening / widget context.
            publishWidgetSnapshot()
        }
    }
    /// Episode id → position / played. Published so episode rows refresh.
    @Published var playbackStates: [String: EpisodePlaybackState] = [:] {
        didSet {
            PodcastPersistence.savePlaybackStates(playbackStates)
            // Played state decides `inboxEpisodes` membership; `historyEpisodes` is built from it.
            inboxEpisodesCache = nil
            historyEpisodesCache = nil
        }
    }
    /// Per-subscription overrides keyed by feed id (`feed-settings.json`).
    @Published var feedSettingsById: [UUID: FeedSettings] = [:] {
        didSet {
            PodcastPersistence.saveFeedSettings(feedSettingsById)
            // Custom titles feed `allEpisodes`, `inboxEpisodes`, and `historyEpisodes` row titles.
            allEpisodesCache = nil
            inboxEpisodesCache = nil
            historyEpisodesCache = nil
        }
    }
    /// Episode id → favorited-at epoch ms (`favorites.json` side map).
    @Published var favoriteAtById: [String: Int64] = [:] {
        didSet { PodcastPersistence.saveFavorites(favoriteAtById) }
    }
    /// Episode id → archived-at epoch ms (`archived.json` side map). Archived ≠ played.
    @Published var archivedAtById: [String: Int64] = [:] {
        didSet {
            PodcastPersistence.saveArchived(archivedAtById)
            // Archived episodes leave `inboxEpisodes`.
            inboxEpisodesCache = nil
        }
    }
    /// Episode id → user bookmarks (`bookmarks.json`). Local-only wall-clock positions; not gpodder.
    @Published var bookmarksByEpisodeId: [String: [EpisodeBookmark]] = [:] {
        didSet { PodcastPersistence.saveBookmarks(bookmarksByEpisodeId) }
    }
    /// Episode id → local-only private note (`episode-notes.json`). Not RSS / gpodder / OPML / HTML / chapters / Share.
    @Published var episodePrivateNotesById: [String: String] = [:] {
        didSet { PodcastPersistence.saveEpisodePrivateNotes(episodePrivateNotesById) }
    }
    /// Feed id → tag names (`feed-tags.json` side map). Tags exist only while assigned.
    @Published var tagsByFeedId: [UUID: [String]] = [:] {
        didSet { PodcastPersistence.saveFeedTags(tagsByFeedId) }
    }
    @Published var isLoading = false
    /// Refresh all, single refresh, and local rescan can overlap (Subscriptions swipe Refresh
    /// during Refresh all); `isLoading` turns off only when the last of them ends.
    private var loadingOperationCount = 0
    private var isRefreshingAllFeeds = false
    private var refreshAllFeedsWaiters: [CheckedContinuation<Void, Never>] = []

    /// Feeds finished (success or failure) during the in-flight `refreshAllFeeds()`.
    /// Honest completion count only — not a byte/percent estimate. Zero when idle.
    @Published var refreshCompletedCount = 0
    /// Feeds that will run in the in-flight `refreshAllFeeds()` (non-empty URL + Keep updated participates).
    /// Zero when idle or for non-bulk `isLoading` work (subscribe / single-feed refresh).
    @Published var refreshTotalCount = 0
    @Published var lastError: String? {
        didSet {
            if lastError == nil { lastErrorFeedId = nil }
        }
    }
    /// Podcast whose refresh failure `lastError` shows, so unsubscribing it clears the banner.
    private var lastErrorFeedId: UUID?
    /// OPML import file/parse error, shown only on the OPML import rows. Kept apart from
    /// `lastError` (Refresh all / single refresh / local rescan) so neither shows or clears the other.
    @Published var opmlImportError: String?
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
        episodePrivateNotesById = PodcastPersistence.loadEpisodePrivateNotes()
        tagsByFeedId = PodcastPersistence.loadFeedTags()
        LocalFolderBookmarkStore.reloadFromPersistence()
        rescanLocalFolderFeedsBestEffort()
        publishWidgetSnapshot()
    }

    /// Reload all Application Support maps after a data backup import (didSet re-persists).
    /// Drops any loaded player first so the pre-import episode cannot stay on screen
    /// or overwrite the restored playback map on the next progress tick.
    func reloadFromPersistence() {
        playback?.discardLoadedEpisodeForBackupImport()
        feeds = PodcastPersistence.loadFeeds()
        queue = PodcastPersistence.loadQueue()
        playbackStates = PodcastPersistence.loadPlaybackStates()
        feedSettingsById = PodcastPersistence.loadFeedSettings()
        favoriteAtById = PodcastPersistence.loadFavorites()
        archivedAtById = PodcastPersistence.loadArchived()
        bookmarksByEpisodeId = PodcastPersistence.loadBookmarks()
        episodePrivateNotesById = PodcastPersistence.loadEpisodePrivateNotes()
        tagsByFeedId = PodcastPersistence.loadFeedTags()
        LocalFolderBookmarkStore.reloadFromPersistence()
        pendingAutoDeleteIds = []
        lastError = nil
        rescanLocalFolderFeedsBestEffort()
        trimHistoryToSizeLimitIfNeeded()
        publishWidgetSnapshot()
    }

    /// Feed preview Confirm Subscribe. Returns the error message, or nil on success.
    /// Leaves the shared `isLoading` / `lastError` alone: a subscribe during Refresh all must not
    /// end the refresh spinner early or wipe its error (the preview shows its own state).
    @discardableResult
    func subscribe(feedUrl: String, credentials: FeedHttpBasicCredentials? = nil) async -> String? {
        // New subscription to https://user:pass@host/feed: keep the password in the Keychain
        // (sent as HTTP Basic on refresh and downloads), not in feeds.json. Entered credentials
        // win. Existing subscriptions keep their stored URL (refresh matches it exactly).
        var subscribeUrl = feedUrl
        var resolvedCredentials = credentials
        if !feeds.contains(where: { $0.feedUrl == feedUrl }),
           let embedded = FeedURLNormalization.embeddedCredentials(in: feedUrl) {
            subscribeUrl = FeedURLNormalization.strippingCredentials(feedUrl)
            if resolvedCredentials?.isUsable != true {
                resolvedCredentials = embedded
            }
        }
        do {
            try await subscribeQuietly(
                feedUrl: subscribeUrl,
                credentials: resolvedCredentials,
                persistCredentials: resolvedCredentials?.isUsable == true
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Remove a subscription.
    /// Clears the feed from the list, per-feed settings, tags, queue items from this feed,
    /// and favorites / archive / bookmarks / episode private notes / playback-history entries for its episodes
    /// and for channel trailers (synthetic ids, not stored in `feed.episodes`).
    /// Also deletes per-feed HTTP Basic credentials from the Keychain (never in JSON).
    /// Local-folder feeds also release the security-scoped bookmark.
    /// Does **not** delete downloaded episode files by itself — UI may call
    /// `DownloadService.deleteDownloads(forFeed:)` **before** this when the user chooses
    /// Unsubscribe and delete downloads (feed-scoped offline files only).
    func unsubscribe(_ staleFeed: PodcastFeed) {
        // The caller's copy can predate a refresh (Unsubscribe dialog left open while Refresh
        // all merged new episodes); clean up with the live episode list.
        let feed = feeds.first(where: { $0.id == staleFeed.id }) ?? staleFeed
        if LocalFolderFeed.isLocalFolderFeed(feed) {
            LocalFolderBookmarkStore.release(feedId: feed.id)
        }
        FeedHttpBasicAuthKeychain.delete(for: feed.id)
        feeds.removeAll { $0.id == feed.id }
        // Its refresh error has nothing left to act on.
        if lastErrorFeedId == feed.id {
            lastError = nil
        }
        feedSettingsById.removeValue(forKey: feed.id)
        tagsByFeedId.removeValue(forKey: feed.id)
        let ids = Set(feed.episodes.map(\.id))
        // Channel trailers are not in `feed.episodes`. Their playback id is
        // `podcast-trailer:<feedUUID>:<mediaURL>`, so a queued, starred, archived,
        // bookmarked, or noted trailer would otherwise survive unsubscribe.
        let trailerPrefix = PodcastTrailer.playbackEpisodeIdPrefix(feedId: feed.id)
        func belongs(_ episodeId: String) -> Bool {
            ids.contains(episodeId) || episodeId.hasPrefix(trailerPrefix)
        }
        queue.removeAll { belongs($0.id) }
        let trailerStateIds = playbackStates.keys.filter { $0.hasPrefix(trailerPrefix) }
        let favoriteTrailerIds = favoriteAtById.keys.filter { $0.hasPrefix(trailerPrefix) }
        let archivedTrailerIds = archivedAtById.keys.filter { $0.hasPrefix(trailerPrefix) }
        let bookmarkTrailerIds = bookmarksByEpisodeId.keys.filter { $0.hasPrefix(trailerPrefix) }
        let noteTrailerIds = episodePrivateNotesById.keys.filter { $0.hasPrefix(trailerPrefix) }
        let clearIds = ids
            .union(trailerStateIds)
            .union(favoriteTrailerIds)
            .union(archivedTrailerIds)
            .union(bookmarkTrailerIds)
            .union(noteTrailerIds)
        for id in clearIds {
            playbackStates.removeValue(forKey: id)
            favoriteAtById.removeValue(forKey: id)
            archivedAtById.removeValue(forKey: id)
            bookmarksByEpisodeId.removeValue(forKey: id)
            episodePrivateNotesById.removeValue(forKey: id)
            pendingAutoDeleteIds.remove(id)
        }
        // Queue didSet publishes before these playback rows are gone. Refresh again
        // so Continue listening on the widget and Watch does not keep the trailer.
        publishWidgetSnapshot()
    }

    // MARK: - Remaining time (list / Home speed estimate)

    /// Effective playback speed for list/Home remaining-time estimates: per-feed
    /// `FeedSettings.playbackSpeed` if set, else `AppSettings.defaultPlaybackSpeed`.
    /// Clamped to ≥ `EpisodeRemainingTime.minimumPlaybackSpeedDivisor` (0.5). Does **not**
    /// use the live player session rate or volume boost.
    func resolvedPlaybackSpeedForRemaining(for episode: PodcastEpisode) -> Float {
        let global = settings?.defaultPlaybackSpeed ?? 1.0
        let raw: Float
        if let feed = feed(containingEpisodeId: episode.id) {
            raw = feedSettings(for: feed.id).resolvedPlaybackSpeed(global: global)
        } else {
            raw = global
        }
        return max(EpisodeRemainingTime.minimumPlaybackSpeedDivisor, raw)
    }

    /// Non-nil speed closure when Settings → Remaining time respects speed is on; else nil
    /// (wall-clock). Safe to pass straight into `EpisodeRemainingTime.summarize`.
    func remainingTimeEffectivePlaybackSpeedClosure() -> ((PodcastEpisode) -> Float)? {
        guard settings?.remainingTimeRespectsSpeed == true else { return nil }
        return { [weak self] episode in
            self?.resolvedPlaybackSpeedForRemaining(for: episode)
                ?? EpisodeRemainingTime.minimumPlaybackSpeedDivisor
        }
    }

    // MARK: - Per-feed settings

    func feedSettings(for feedId: UUID) -> FeedSettings {
        feedSettingsById[feedId] ?? .default
    }

    func setFeedSettings(_ settings: FeedSettings, for feedId: UUID) {
        let previous = feedSettings(for: feedId)
        let previousSpeed = previous.playbackSpeed
        let previousTitle = previous.customTitle
        if settings.isDefault {
            feedSettingsById.removeValue(forKey: feedId)
        } else {
            feedSettingsById[feedId] = settings
        }
        // Mirror Android SpeedPresetChangedEvent: only when playbackSpeed actually changes.
        // Other feed prefs must not clobber a temporary player session rate.
        if previousSpeed != settings.playbackSpeed {
            playback?.applyEffectivePlaybackSpeedIfCurrent(feedId: feedId)
        }
        // Lock screen / Control Center and the Continue widget read the display title,
        // but they do not refresh while paused. Pin, skip intro, and other prefs do not.
        if previousTitle != settings.customTitle {
            playback?.refreshNowPlayingTitleIfCurrent(feedId: feedId)
            publishWidgetSnapshot()
        }
    }

    func updateFeedSettings(for feedId: UUID, _ mutate: (inout FeedSettings) -> Void) {
        var current = feedSettings(for: feedId)
        mutate(&current)
        setFeedSettings(current, for: feedId)
    }

    /// Local Keep-at-top / pin preference (`FeedSettings.isPinned`; default false).
    func isPinned(feedId: UUID) -> Bool {
        feedSettings(for: feedId).isPinned
    }

    /// Sets Keep at top for this subscription (persists in `feed-settings.json`; not gpodder).
    func setPinned(feedId: UUID, _ pinned: Bool) {
        updateFeedSettings(for: feedId) { $0.isPinned = pinned }
    }

    /// Toggles Keep at top for this subscription.
    func togglePinned(feedId: UUID) {
        setPinned(feedId: feedId, !isPinned(feedId: feedId))
    }

    /// Clears Keep at top (`isPinned = false`) for every **subscribed** feed that is pinned.
    /// Mutates `feedSettingsById` once (single `feed-settings.json` persist) — same batch spirit as
    /// `renameTag`. Does **not** unsubscribe, change tags, or change sort preference.
    /// Callers must confirm first (Subscriptions toolbar `confirmationDialog`).
    /// Existing Pinned filter chip resets via `onChange(of: store.feedSettingsById)`.
    /// - Returns: number of feeds that were unpinned (0 when none pinned).
    @discardableResult
    func unpinAll() -> Int {
        let pinnedIds = feeds.filter { isPinned(feedId: $0.id) }.map(\.id)
        guard !pinnedIds.isEmpty else { return 0 }
        var next = feedSettingsById
        for feedId in pinnedIds {
            var settings = next[feedId] ?? .default
            guard settings.isPinned else { continue }
            settings.isPinned = false
            if settings.isDefault {
                next.removeValue(forKey: feedId)
            } else {
                next[feedId] = settings
            }
        }
        feedSettingsById = next
        return pinnedIds.count
    }

    /// User-facing podcast name for lists / nav / player / search (customTitle ?? RSS title).
    func displayTitle(for feed: PodcastFeed) -> String {
        feed.displayTitle(settings: feedSettings(for: feed.id))
    }

    /// Display title for a known feed id; `nil` when the feed is not in the library.
    func displayTitle(forFeedId feedId: UUID) -> String? {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return nil }
        return displayTitle(for: feed)
    }

    /// Trimmed display title for a known feed, or nil when the feed provides no usable title.
    /// Filter chips use this to avoid presenting a generic label as feed metadata.
    func nonEmptyDisplayTitle(for feed: PodcastFeed) -> String? {
        let trimmed = displayTitle(for: feed).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed display title for a known feed id, or nil when the feed is missing/title-less.
    func nonEmptyDisplayTitle(forFeedId feedId: UUID) -> String? {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return nil }
        return nonEmptyDisplayTitle(for: feed)
    }

    /// Display title for the feed containing `episodeId`, or empty string when unknown.
    func displayTitle(containingEpisodeId episodeId: String) -> String {
        guard let feed = feed(containingEpisodeId: episodeId) else { return "" }
        return displayTitle(for: feed)
    }

    /// Live lookup first; a download whose episode has since left the feed falls back to the
    /// subscription id recorded when it finished.
    func downloadFeed(for item: DownloadedEpisode) -> PodcastFeed? {
        if let feed = feed(containingEpisodeId: item.episode.id) {
            return feed
        }
        guard let feedId = item.feedId else { return nil }
        return feeds.first { $0.id == feedId }
    }

    /// `downloadFeed(for:)` display title, else the title recorded at download time, else "".
    func downloadDisplayTitle(for item: DownloadedEpisode) -> String {
        if let feed = downloadFeed(for: item) {
            return displayTitle(for: feed)
        }
        return item.feedTitle ?? ""
    }

    /// Serial narrative default (one-shot / nil-only): when channel `itunes:type` canonicalizes to
    /// `serial` and per-feed `episodeSort` is still `nil`, set **Oldest first** once.
    /// - Never invents type (parsed channel only via `ItunesTypeParsing.canonical`).
    /// - Does **not** override a user-chosen per-feed sort (any non-nil value).
    /// - Does **not** change global `AppSettings.feedEpisodeSort`.
    /// - If type later leaves serial, does **not** auto-clear (leave settings as-is).
    /// Capsule UI remains display-only; this only writes `FeedSettings.episodeSort` under the nil rule.
    func applySerialOldestFirstHeuristicIfNeeded(for feed: PodcastFeed) {
        guard feed.isItunesTypeSerial else { return }
        let current = feedSettings(for: feed.id)
        guard current.episodeSort == nil else { return }
        updateFeedSettings(for: feed.id) { $0.episodeSort = .oldestFirst }
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
        if oldName == newName { return }
        // A case- or accent-only change (news → News) matches the old name, so the
        // vocabulary lookup would hand back the old spelling and the rename did nothing.
        let display = FeedTags.equal(oldName, newName)
            ? newName
            : allTags.first(where: { FeedTags.equal($0, newName) }) ?? newName
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

    /// Returns this refresh's own error (nil on success), so a caller does not read a Refresh all
    /// error that the shared `lastError` may hold while both run.
    @discardableResult
    func refresh(_ feed: PodcastFeed) async -> String? {
        guard !feed.feedUrl.isEmpty else {
            return nil
        }
        if LocalFolderFeed.isLocalFolderFeed(feed) {
            return await refreshLocalFolderFeed(feed)
        }
        let wasSubscribed = feeds.contains(where: { $0.feedUrl == feed.feedUrl })
        var newcomers: [PodcastEpisode] = []
        var ownError: String?
        if wasSubscribed {
            // Same as subscribe(), except a podcast unsubscribed while this fetch runs
            // (Subscriptions swipe Refresh, then Unsubscribe) is not added back.
            // Do not clear lastError here: a success on another feed must leave this
            // podcast's banner up (clear only via clearRefreshError on success below).
            beginLoadingOperation()
            do {
                newcomers = try await subscribeQuietly(feedUrl: feed.feedUrl, onlyIfSubscribed: true)
            } catch {
                ownError = error.localizedDescription
                setRefreshError(error.localizedDescription, feed: feeds.first(where: { $0.feedUrl == feed.feedUrl }) ?? feed)
            }
            endLoadingOperation()
            if ownError == nil {
                clearRefreshError(ifFeed: feeds.first(where: { $0.feedUrl == feed.feedUrl }) ?? feed)
            }
        } else {
            ownError = await subscribe(feedUrl: feed.feedUrl)
        }
        var newBatches: [NewEpisodeBatch] = []
        if wasSubscribed, let updated = feeds.first(where: { $0.feedUrl == feed.feedUrl }) {
            if !newcomers.isEmpty {
                newBatches = [
                    NewEpisodeBatch(
                        feedTitle: displayTitle(for: updated),
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
        return ownError
    }

    func isInQueue(_ episodeId: String) -> Bool {
        queue.contains { $0.id == episodeId }
    }

    func enqueue(_ episode: PodcastEpisode) {
        guard !queue.contains(where: { $0.id == episode.id }) else { return }
        // Currently playing and not yet queued: append would put it at the tail, so
        // `nextQueueEpisode(after:)` returns nil and Continuous Queue mode stops even
        // though episodes were already queued (before add, next was the head). Insert at
        // the head — same slot Play Next uses when current is not queued — so B, C, …
        // still follow. Other episodes stay append-at-end.
        if episode.id == playback?.currentEpisode?.id {
            queue.insert(episode, at: 0)
        } else {
            queue.append(episode)
        }
    }

    /// AntennaPod-style **Play Next**: place `episode` immediately after the currently
    /// playing queue item (or at the head if nothing is playing / current is not queued).
    /// If already in the queue, moves it (no duplicate). Persists via `queue` `didSet`.
    ///
    /// Continuous playback uses `nextQueueEpisode(after:)`: when current *is* in the queue,
    /// Play Next becomes the auto-next item; when current is *not* queued, head-of-queue is
    /// already what auto-next uses after finish. (`enqueue` of the playing episode also uses
    /// the head so Continuous Queue mode is not broken by an append at the tail.)
    /// Play Next on the episode that is already playing and queued does not move it.
    func playNext(_ episode: PodcastEpisode, currentlyPlayingId: String?) {
        // This episode is already the playing queue item. "After current" is its own
        // slot. Removing it first would make the playing id look unqueued and jump it
        // to the head, so the previous item becomes auto-next.
        if episode.id == currentlyPlayingId,
           queue.contains(where: { $0.id == episode.id }) {
            return
        }
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

    /// Remove **played** episodes from the **full** persisted queue (`isPlayed`). Persists via `queue` `didSet`.
    /// Does not stop playback, change progress, unmark played, or delete downloads — queue entries only
    /// (same honesty as per-row `removeFromQueue` / `clearQueue`). If the currently playing episode is
    /// played and queued, it leaves the queue but playback continues. Callers must confirm first;
    /// safe while queue lock is on (reorder-only). Returns how many entries were removed.
    @discardableResult
    func removePlayedFromQueue() -> Int {
        let before = queue.count
        queue.removeAll { isPlayed($0.id) }
        return before - queue.count
    }

    /// Mark every unplayed, non-archived episode in the **full** persisted queue as played.
    ///
    /// Queue uses the same mark-played semantics as the row action: `markPlayed` removes each
    /// episode from the queue by default, while preserving its playback state and applying
    /// configured auto-delete-after-playing behavior. The catalog is snapshotted before mutation
    /// so removing an item does not skip the next one. Archived unplayed episodes are skipped,
    /// matching the sibling bulk Mark all as played actions. Callers must confirm first.
    func markAllQueuePlayed() {
        let ids = markAllQueuePlayedCandidateIds
        for id in ids {
            markPlayed(id)
        }
    }

    /// Number of unplayed, non-archived episodes in the full persisted queue.
    /// This deliberately ignores the Queue played/podcast/search filters.
    func markAllQueuePlayedCandidateCount() -> Int {
        markAllQueuePlayedCandidateIds.count
    }

    private var markAllQueuePlayedCandidateIds: [String] {
        queue
            .filter { !isPlayed($0.id) && !isArchived($0.id) }
            .map(\.id)
    }

    /// Mark every played episode in the **full** persisted queue as unplayed.
    ///
    /// This includes archived played episodes, matching the sibling bulk Mark all as unplayed
    /// actions. `markUnplayed` only changes playback state, so every episode stays in the queue;
    /// downloads, playback, and archive state are unchanged. Callers must confirm first.
    func markAllQueueUnplayed() {
        let ids = markAllQueueUnplayedCandidateIds
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Number of played episodes in the full persisted queue, including archived episodes.
    /// This deliberately ignores the Queue played/podcast/search filters.
    func markAllQueueUnplayedCandidateCount() -> Int {
        markAllQueueUnplayedCandidateIds.count
    }

    private var markAllQueueUnplayedCandidateIds: [String] {
        queue
            .filter { isPlayed($0.id) }
            .map(\.id)
    }

    /// Archive every non-archived episode in the **full** persisted queue.
    ///
    /// This deliberately ignores the Queue played/podcast/search filters. Archiving matches the
    /// existing single-item `archive` path: it only writes archive state, so queue entries,
    /// played state, playback, and downloads remain unchanged. Existing archive timestamps are
    /// preserved and all new timestamps are persisted in one `archivedAtById` write. Callers must
    /// confirm first (Queue toolbar `confirmationDialog`).
    func archiveAllQueue() {
        let ids = queue
            .map(\.id)
            .filter { !isArchived($0) }
        guard !ids.isEmpty else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
    }

    /// Number of non-archived episodes in the full persisted queue.
    /// This deliberately ignores the Queue played/podcast/search filters.
    func archiveAllQueueCandidateCount() -> Int {
        queue.filter { !isArchived($0.id) }.count
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

    /// Sort the **full** persisted queue by episode title (A–Z or Z–A).
    /// Uses `localizedCaseInsensitiveCompare` on trimmed titles. Episodes with **empty** titles
    /// sort **last** in both modes; equal titles (or both empty) break ties by stable episode `id`.
    /// Persists via `queue` `didSet` (same path as `moveQueue` / `shuffleQueue` / `reverseQueue` /
    /// `sortQueueByPublishDate` / `sortQueueByDuration`). No-op when fewer than 2 items.
    /// Does **not** change `PlaybackService.currentEpisode` identity, seek, or stop playback —
    /// the currently playing episode (if any) **moves with its episode id** to its new list index
    /// (it is not pinned at the same index). Continuous next still uses `nextQueueEpisode(after:)`
    /// by id, so auto-next becomes whatever follows that id after the sort.
    /// One-shot reorder of `queue.json` — **not** a persistent filter preference (unlike Inbox/`inboxSort`).
    /// Callers must gate on queue unlock (reorder-only lock, same as Shuffle/Reverse/Sort by date/duration) and confirm first.
    func sortQueueByTitle(ascending: Bool) {
        guard queue.count >= 2 else { return }
        queue = queue.sorted { lhs, rhs in
            let lt = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let rt = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (lt.isEmpty, rt.isEmpty) {
            case (false, true):
                return true // non-empty before empty
            case (true, false):
                return false
            case (true, true):
                return lhs.id < rhs.id
            case (false, false):
                let cmp = lt.localizedCaseInsensitiveCompare(rt)
                if cmp != .orderedSame {
                    return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
                }
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
        // Non-finite position makes JSONEncoder throw; encode then skips the whole playback.json write.
        guard positionSeconds.isFinite else { return }
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
        if resetPosition {
            playback?.holdMarkPlayedPositionReset(for: episodeId)
        } else {
            playback?.releaseMarkPlayedPositionReset(for: episodeId)
        }
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
        // Switching away near the end would otherwise smart-mark it played again.
        playback?.suppressSmartMarkAfterMarkUnplayed(for: episodeId)
        // Leave the reset hold. Releasing it here lets the next progress
        // tick write the live playhead back, so a later play resumes mid-episode.
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

    /// Next Queue item after `episodeId` for continuous playback **Queue** mode (**Queue order only**).
    /// If `episodeId` is in the queue, returns the following entry (or `nil` at the tail).
    /// If not queued, returns the head of the queue (same honesty as Play Next when current is not queued).
    /// Does **not** walk the feed/podcast episode list — Same podcast mode uses `nextSamePodcastEpisode(after:)`.
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

    /// Next eligible episode of the **same podcast/feed** for continuous playback **Same podcast** mode.
    ///
    /// Order: effective feed episode sort (`FeedSettings.episodeSort` ?? global `AppSettings.feedEpisodeSort`
    /// — Newest / Oldest / Shortest / Longest / Title A–Z / Z–A; same rules as Feed detail).
    /// Walks **forward** from the finished episode’s index in that list (no wrap). Skips **archived**
    /// and **already played** episodes. Returns `nil` when the episode has no owning feed, is missing
    /// from the feed list, or no eligible next remains.
    /// Does **not** consult or jump the Queue (Queue mode stays `nextQueueEpisode`).
    /// Callers snapshot before `markPlayed` so the finished id is still findable; the finished
    /// episode itself is never returned (walk starts at index + 1).
    func nextSamePodcastEpisode(after episodeId: String) -> PodcastEpisode? {
        guard let feed = feed(containingEpisodeId: episodeId) else { return nil }
        // Synthetic channel trailer ids are not in `feed.episodes` — no same-podcast next.
        guard feed.episodes.contains(where: { $0.id == episodeId }) else { return nil }
        let global = settings?.feedEpisodeSort ?? .newestFirst
        let sort = feedSettings(for: feed.id).resolvedEpisodeSort(global: global)
        let ordered = Self.episodesSortedForContinuous(feed.episodes, sort: sort) { episode in
            EpisodeRemainingTime.knownDurationSeconds(
                for: episode,
                savedDurationSeconds: playbackState(for: episode.id).durationSeconds
            )
        }
        guard let index = ordered.firstIndex(where: { $0.id == episodeId }) else { return nil }
        let after = ordered.index(after: index)
        guard after < ordered.endIndex else { return nil }
        for candidate in ordered[after...] {
            if isArchived(candidate.id) { continue }
            if isPlayed(candidate.id) { continue }
            return candidate
        }
        return nil
    }

    /// Sort feed episodes for continuous Same-podcast advance (mirrors Feed detail sort honesty).
    private static func episodesSortedForContinuous(
        _ episodes: [PodcastEpisode],
        sort: FeedEpisodeSort,
        knownDuration: (PodcastEpisode) -> Double?
    ) -> [PodcastEpisode] {
        episodes.sorted { lhs, rhs in
            switch sort {
            case .newestFirst:
                let l = lhs.pubDateEpochMs ?? Int64.min
                let r = rhs.pubDateEpochMs ?? Int64.min
                if l != r { return l > r }
                return continuousTitleTiebreak(lhs, rhs)
            case .oldestFirst:
                let l = lhs.pubDateEpochMs ?? Int64.max
                let r = rhs.pubDateEpochMs ?? Int64.max
                if l != r { return l < r }
                return continuousTitleTiebreak(lhs, rhs)
            case .shortestFirst, .longestFirst:
                let shortestFirst = sort == .shortestFirst
                switch (knownDuration(lhs), knownDuration(rhs)) {
                case let (l?, r?):
                    if l != r {
                        return shortestFirst ? (l < r) : (l > r)
                    }
                    return continuousTitleTiebreak(lhs, rhs)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return continuousTitleTiebreak(lhs, rhs)
                }
            case .titleAscending, .titleDescending:
                return continuousTitleSort(lhs, rhs, ascending: sort == .titleAscending)
            }
        }
    }

    private static func continuousTitleTiebreak(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode) -> Bool {
        let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func continuousTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
        let lt = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rt = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (lt.isEmpty, rt.isEmpty) {
        case (false, true):
            return true
        case (true, false):
            return false
        case (true, true):
            return lhs.id < rhs.id
        case (false, false):
            let cmp = lt.localizedCaseInsensitiveCompare(rt)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            return lhs.id < rhs.id
        }
    }

    /// Episode id → index in `feeds` of the first feed whose `episodes` holds it (the same
    /// feed `first(where:)` found). Lists call `feed(containingEpisodeId:)` per row or per
    /// item on every 0.5s playback tick; scanning the library each time was O(library) per
    /// call (Inbox podcast chips: per Inbox episode). Only input: `feeds`, whose observer
    /// clears this.
    private var feedIndexByEpisodeIdCache: [String: Int]?

    private var feedIndexByEpisodeId: [String: Int] {
        if let cached = feedIndexByEpisodeIdCache {
            return cached
        }
        var built: [String: Int] = [:]
        for (index, feed) in feeds.enumerated() {
            for episode in feed.episodes where built[episode.id] == nil {
                built[episode.id] = index
            }
        }
        feedIndexByEpisodeIdCache = built
        return built
    }

    /// Feed that owns the episode (for Now Playing artist / artwork).
    func feed(containingEpisodeId episodeId: String) -> PodcastFeed? {
        if let index = feedIndexByEpisodeId[episodeId] {
            return feeds[index]
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
    /// Channel `podcast:trailer` playback uses a synthetic id that is not stored in
    /// `feed.episodes`; resolve it the same way History does so Library → Bookmarks
    /// can start that trailer at a saved mark when it is not already loaded.
    func episode(id episodeId: String) -> PodcastEpisode? {
        // Same first feed the old per-feed scan stopped at (`feedIndexByEpisodeId`); the mini
        // player alone calls this about ten times per 0.5s playback tick.
        if let index = feedIndexByEpisodeId[episodeId],
           let episode = feeds[index].episodes.first(where: { $0.id == episodeId }) {
            return episode
        }
        if let queued = queue.first(where: { $0.id == episodeId }) {
            return queued
        }
        return trailerEpisodeForHistory(id: episodeId)?.episode
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
        // Read by the Inbox tab badge (RootTabView) and ~15 times per InboxView body, all of
        // which rerun on every 0.5s playback tick. Rebuild only when an input below changes.
        if let cached = inboxEpisodesCache {
            return cached
        }
        let built = buildInboxEpisodes()
        inboxEpisodesCache = built
        return built
    }

    /// Last `inboxEpisodes` result. Inputs: `feeds`, `playbackStates` (`isPlayed`),
    /// `archivedAtById` (`isArchived`), `feedSettingsById` (`displayTitle`). Each one's
    /// observer clears this.
    private var inboxEpisodesCache: [InboxEpisode]?

    private func buildInboxEpisodes() -> [InboxEpisode] {
        var items: [InboxEpisode] = []
        for feed in feeds {
            for episode in feed.episodes where !isPlayed(episode.id) && !isArchived(episode.id) {
                items.append(InboxEpisode(episode: episode, feedTitle: displayTitle(for: feed)))
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
    /// Remaining = sum of `max(0, duration − position)` when duration known; unknown
    /// durations skipped (`unknownCount`); live `PlaybackService` position/duration when that
    /// episode is current (if `playback` is wired). **Played** (not current) → 0 (defensive —
    /// set is already unplayed). When `AppSettings.remainingTimeRespectsSpeed` is on, divides
    /// each episode by effective feed/default speed (estimate; not session rate). Omits feeds
    /// with zero unplayed (callers treat missing as 0 / hide remaining).
    func unplayedRemainingByFeedId() -> [UUID: FeedUnplayedRemainingSummary] {
        var result: [UUID: FeedUnplayedRemainingSummary] = [:]
        result.reserveCapacity(feeds.count)
        let currentId = playback?.currentEpisode?.id
        let liveDur = playback?.durationSeconds ?? 0
        let livePos = playback?.positionSeconds ?? 0
        let speedClosure = remainingTimeEffectivePlaybackSpeedClosure()
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
                savedPositionSeconds: { positionSeconds(for: $0) },
                effectivePlaybackSpeed: speedClosure
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
        // AllEpisodesView reads this ~20 times per body, and the body reruns on every
        // 0.5s playback tick. Rebuild only when `feeds` or `feedSettingsById` change.
        if let cached = allEpisodesCache {
            return cached
        }
        let built = buildAllEpisodes()
        allEpisodesCache = built
        return built
    }

    /// Last `allEpisodes` result; cleared by the `feeds` and `feedSettingsById` observers.
    private var allEpisodesCache: [InboxEpisode]?

    private func buildAllEpisodes() -> [InboxEpisode] {
        var items: [InboxEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                items.append(InboxEpisode(episode: episode, feedTitle: displayTitle(for: feed)))
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

    /// Append unplayed, non-archived, not-already-queued episodes from the soft-capped All Episodes catalog.
    /// Uses `allEpisodes` store order (newest-first by publish date within the newest-500 soft cap),
    /// not the UI status, podcast, type, sort, or search filters. This follows the same eligibility
    /// policy as Feed detail `enqueueAllUnplayedFromFeed`: played, archived, and already-queued
    /// episodes are skipped. Uses `enqueue` (append), not `playNext`, and remains allowed while the
    /// queue lock is on.
    /// Callers must confirm first (All Episodes toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllUnplayedEpisodes() -> Int {
        let candidates = enqueueAllUnplayedEpisodesCandidates()
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Eligible episodes for All Episodes **Add all unplayed to queue**. Shared by the confirmation
    /// count and `enqueueAllUnplayedEpisodes`; the catalog is always the newest-500 soft cap.
    func enqueueAllUnplayedEpisodesCandidates() -> [PodcastEpisode] {
        allEpisodes
            .map(\.episode)
            .filter { episode in
                !isPlayed(episode.id) && !isArchived(episode.id) && !isInQueue(episode.id)
            }
    }

    /// Mark every unplayed, non-archived episode in the soft-capped All Episodes catalog as played.
    /// The catalog is the newest 500 episodes by publish date, matching `allEpisodes` and the
    /// Add all / Play random / Copy / Share catalog. This deliberately ignores UI status, podcast,
    /// type, sort, and search filters; older episodes beyond the soft cap are not included.
    /// Snapshots eligible ids first, then calls `markPlayed` per id so auto-delete-after-playing,
    /// queue removal, rating prompts, and other per-episode side effects still apply. Uses the same
    /// unplayed + non-archived policy as feed `markAllPlayed(inFeedId:)`.
    /// Callers must confirm first (All Episodes toolbar `confirmationDialog`).
    func markAllEpisodesPlayed() {
        let ids = allEpisodes
            .map(\.episode)
            .filter { !isPlayed($0.id) && !isArchived($0.id) }
            .map(\.id)
        for id in ids {
            markPlayed(id)
        }
    }

    func markAllFavoritesPlayed() {
        for id in markAllFavoritesPlayedCandidateIds {
            markPlayed(id)
        }
    }

    func markAllFavoritesPlayedCandidateCount() -> Int {
        markAllFavoritesPlayedCandidateIds.count
    }

    private var markAllFavoritesPlayedCandidateIds: [String] {
        favoriteEpisodes
            .map(\.episode)
            .filter { !isPlayed($0.id) && !isArchived($0.id) }
            .map(\.id)
    }

    /// Mark every played episode in the full Favorites catalog as unplayed, including archived
    /// episodes. This deliberately ignores podcast, search, and sort filters. IDs are snapshotted
    /// before calling `markUnplayed`; the per-episode path does not delete downloads, remove queue
    /// items, stop playback, or unarchive episodes. Callers must confirm first.
    func markAllFavoritesUnplayed() {
        let ids = markAllFavoritesUnplayedCandidateIds
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Number of played episodes in the full Favorites catalog, including archived episodes.
    /// This intentionally ignores all Favorites view filters.
    func markAllFavoritesUnplayedCandidateCount() -> Int {
        markAllFavoritesUnplayedCandidateIds.count
    }

    private var markAllFavoritesUnplayedCandidateIds: [String] {
        favoriteEpisodes
            .map(\.episode)
            .filter { isPlayed($0.id) }
            .map(\.id)
    }

    /// Mark every eligible completed download as played.
    ///
    /// Uses the full `DownloadService.downloads` catalog, not the Downloads view's chip,
    /// podcast, search, or sort filters. Unplayed archived episodes are skipped, matching
    /// All Episodes / feed Mark all as played. IDs are snapshotted before calling `markPlayed`
    /// so auto-delete-after-playing, queue removal, and other per-episode side effects still
    /// apply even when marking played removes the local file from the download catalog.
    /// This method does not delete files itself; `markPlayed` may trigger the configured
    /// auto-delete-after-playing behavior. Callers must confirm first.
    func markAllDownloadsPlayed() {
        let ids = markAllDownloadsPlayedCandidateIds
        for id in ids {
            markPlayed(id)
        }
    }

    /// Number of unplayed, non-archived episodes in the full completed Downloads catalog.
    /// This intentionally ignores all Downloads view filters.
    func markAllDownloadsPlayedCandidateCount() -> Int {
        markAllDownloadsPlayedCandidateIds.count
    }

    private var markAllDownloadsPlayedCandidateIds: [String] {
        guard let downloads else { return [] }
        return downloads.downloads
            .map(\.episode)
            .filter { !isPlayed($0.id) && !isArchived($0.id) }
            .map(\.id)
    }

    /// Mark every played episode in the full completed Downloads catalog as unplayed.
    ///
    /// This includes archived played episodes, matching feed / All Episodes Mark all as
    /// unplayed. IDs are snapshotted before calling `markUnplayed`; the per-episode path does
    /// not delete download files, remove queue items, stop playback, or unarchive episodes.
    /// This intentionally ignores all Downloads view filters. Callers must confirm first.
    func markAllDownloadsUnplayed() {
        let ids = markAllDownloadsUnplayedCandidateIds
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Number of played episodes in the full completed Downloads catalog.
    /// This intentionally ignores all Downloads view filters.
    func markAllDownloadsUnplayedCandidateCount() -> Int {
        markAllDownloadsUnplayedCandidateIds.count
    }

    private var markAllDownloadsUnplayedCandidateIds: [String] {
        guard let downloads else { return [] }
        return downloads.downloads
            .map(\.episode)
            .filter { isPlayed($0.id) }
            .map(\.id)
    }

    /// Archive every non-archived episode in the full completed Downloads catalog.
    ///
    /// This intentionally ignores the Downloads view's chip, podcast, search, and sort filters.
    /// Completed downloads only are represented by `DownloadService.downloads`; in-flight and
    /// waiting transfers are not episodes in this catalog. Archiving is independent of played
    /// state and does not mark played, delete files, clear the queue, or trigger auto-delete after
    /// playing. Writes `archivedAtById` once and preserves existing archive timestamps. Callers
    /// must confirm first (Downloads toolbar `confirmationDialog`).
    func archiveAllDownloads() {
        guard let downloads else { return }
        let ids = downloads.downloads
            .map(\.episode.id)
            .filter { !isArchived($0) }
        guard !ids.isEmpty else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
    }

    /// Mark every played episode in the soft-capped All Episodes catalog as unplayed.
    /// The catalog is the newest 500 episodes by publish date, matching `allEpisodes` and the
    /// Add all / Play random / Copy / Share catalog. This deliberately ignores UI status, podcast,
    /// type, sort, and search filters; older episodes beyond the soft cap are not included.
    /// Includes archived played episodes, mirroring feed `markAllUnplayed(inFeedId:)`.
    /// Snapshots eligible ids first, then calls `markUnplayed` per id (same as per-row: does not
    /// delete downloads, remove queue, stop playback, or unarchive).
    /// Callers must confirm first (All Episodes toolbar `confirmationDialog`).
    func markAllEpisodesUnplayed() {
        let ids = allEpisodes
            .map(\.episode.id)
            .filter { isPlayed($0) }
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Archive every non-archived episode in the soft-capped All Episodes catalog.
    /// The catalog is the newest 500 episodes by publish date, matching `allEpisodes` and the
    /// Add all / Mark all / Play random / Copy / Share catalog. This deliberately ignores UI
    /// status, podcast, type, sort, and search filters; older episodes beyond the soft cap are
    /// not included. Archiving is independent from played state and does not mark played, delete
    /// downloads, clear the queue, or apply any other per-episode side effects.
    /// Callers must confirm first (All Episodes toolbar `confirmationDialog`).
    func archiveAllEpisodes() {
        let ids = allEpisodes
            .map(\.episode.id)
            .filter { !isArchived($0) }
        guard !ids.isEmpty else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
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
            currentFeedTitle: current.flatMap { episode in
                let title = displayTitle(containingEpisodeId: episode.id)
                return title.isEmpty ? nil : title
            },
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

    /// Home Recently updated cards, newest episode `pubDateEpochMs` first.
    /// Equal dates (including both missing) break ties by the name on the card
    /// (custom title when set, else the RSS title). A raw RSS compare puts a
    /// renamed podcast where the old name sorts, so the visible label and the
    /// row disagree. Same tiebreak as Subscriptions Recently updated.
    var recentlyUpdatedFeeds: [PodcastFeed] {
        feeds.sorted { lhs, rhs in
            let l = lhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
            let r = rhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
            if l != r { return l > r }
            return displayTitle(for: lhs).localizedCaseInsensitiveCompare(displayTitle(for: rhs)) == .orderedAscending
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

    /// Mark every played episode from the full stored feed catalog behind Inbox as unplayed.
    ///
    /// `inboxEpisodes` is intentionally unplayed-only, so a reverse bulk action cannot use that
    /// derived list: once an episode is played it leaves Inbox. The full subscribed-feed catalog
    /// is the stable catalog scope for this action; archived played episodes are included. IDs are
    /// snapshotted before calling `markUnplayed`; this does not delete downloads, remove queue
    /// items, stop playback, or unarchive episodes. Callers must confirm first.
    func markAllInboxUnplayed() {
        let ids = feeds
            .flatMap(\.episodes)
            .filter { isPlayed($0.id) }
            .map(\.id)
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Number of played episodes in the full stored feed catalog behind Inbox, including archived.
    func markAllInboxUnplayedCandidateCount() -> Int {
        feeds
            .flatMap(\.episodes)
            .filter { isPlayed($0.id) }
            .count
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

    /// Append unplayed, non-archived, not-already-queued episodes from the full Inbox catalog.
    /// Inbox is normally already unplayed-only, but the explicit status/archive guards keep this
    /// helper honest if the derived Inbox policy changes. Uses newest-first store order, not UI
    /// sort, podcast, episode-type, or search filters. Queue lock does not block enqueue.
    /// Callers must confirm first (Inbox toolbar `confirmationDialog`).
    @discardableResult
    func enqueueAllUnplayedInbox() -> Int {
        let candidates = enqueueAllUnplayedInboxCandidates()
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Eligible episodes for Inbox **Add all unplayed to queue**.
    func enqueueAllUnplayedInboxCandidates() -> [PodcastEpisode] {
        inboxEpisodes
            .map(\.episode)
            .filter { episode in
                !isPlayed(episode.id) && !isArchived(episode.id) && !isInQueue(episode.id)
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

    /// Archive every non-archived episode in one feed (bulk).
    ///
    /// Uses the full stored catalog for this feed only, not Feed detail status, episode-type,
    /// search, or sort filters. Existing archive timestamps are preserved and all new timestamps
    /// are persisted in one `archivedAtById` write. Archiving does not mark played, delete
    /// downloads, clear the queue, or change playback. Callers must confirm first.
    func archiveAll(inFeedId feedId: String) {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return }
        let ids = feed.episodes
            .filter { !isArchived($0.id) }
            .map(\.id)
        guard !ids.isEmpty else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
    }

    /// Number of non-archived episodes in one feed's full stored catalog.
    /// This deliberately ignores Feed detail status, episode-type, search, and sort filters.
    func archiveAllCandidateCount(inFeedId feedId: String) -> Int {
        feeds.first(where: { $0.id == feedId })?.episodes
            .filter { !isArchived($0.id) }
            .count ?? 0
    }

    /// Mark every **played** episode in one feed as unplayed (bulk), **including archived**.
    /// Archive policy: prefer mark unplayed even if archived (inverted of Mark all as played
    /// which skips archived unplayed — here any `isPlayed` on this feed is eligible).
    /// Snapshots eligible ids first, then calls `markUnplayed` per id (same as per-row:
    /// does **not** delete downloads, remove queue, stop playback, or unarchive).
    /// Feed-scoped only. Callers must confirm first (Feed detail toolbar).
    func markAllUnplayed(inFeedId feedId: String) {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return }
        let ids = feed.episodes
            .filter { isPlayed($0.id) }
            .map(\.id)
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Append every episode from one feed that is not already queued (bulk).
    /// Uses the **full** stored feed episode catalog (`feed.episodes`), sorted **newest-first**
    /// by `pubDateEpochMs` (missing dates last; title tiebreak — same spirit as Feed Download all unplayed).
    /// Does **not** follow UI `feedEpisodeSort`, chip filter (`feedEpisodeFilter`), or searchable filter
    /// — same full-feed honesty as Mark all as played / Download all unplayed.
    /// Includes played and archived episodes (unlike Download all unplayed / Mark all /
    /// **Add all unplayed to queue** eligibility).
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

    /// Append **unplayed**, **non-archived**, not-already-queued episodes from one feed (bulk).
    /// Uses the **full** stored feed episode catalog (`feed.episodes`) — **not** chip filter
    /// (`feedEpisodeFilter`) or searchable filter — same full-feed honesty as Download all unplayed
    /// / Mark all as played / Add all to queue.
    /// Order: effective feed episode sort (`FeedSettings.episodeSort` ?? global
    /// `AppSettings.feedEpisodeSort` — Newest / Oldest / Shortest / Longest / Title A–Z / Z–A;
    /// same rules as Feed detail list / continuous Same-podcast).
    /// Skips played, archived, and already-queued ids (no duplicates). Uses `enqueue` (append),
    /// not `playNext`. Safe while queue lock is on (reorder-only — enqueue stays allowed).
    /// Callers must confirm first (Feed detail toolbar `confirmationDialog`).
    /// Distinct from `enqueueAllFromFeed` (which includes played/archived, newest-pubDate-first).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllUnplayedFromFeed(_ feed: PodcastFeed) -> Int {
        let candidates = enqueueAllUnplayedFromFeedCandidates(feed)
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Eligible episodes for Feed detail **Add all unplayed to queue** (full catalog; effective
    /// episode sort). Shared by confirm count and `enqueueAllUnplayedFromFeed`.
    func enqueueAllUnplayedFromFeedCandidates(_ feed: PodcastFeed) -> [PodcastEpisode] {
        let global = settings?.feedEpisodeSort ?? .newestFirst
        let sort = feedSettings(for: feed.id).resolvedEpisodeSort(global: global)
        let ordered = Self.episodesSortedForContinuous(feed.episodes, sort: sort) { episode in
            EpisodeRemainingTime.knownDurationSeconds(
                for: episode,
                savedDurationSeconds: playbackState(for: episode.id).durationSeconds
            )
        }
        return ordered.filter { episode in
            !isPlayed(episode.id) && !isArchived(episode.id) && !isInQueue(episode.id)
        }
    }

    /// Archived episodes across feeds, newest archived first.
    /// Also includes an archived channel trailer (synthetic id, not in `feed.episodes`)
    /// and queue-only copies.
    var archivedEpisodes: [ArchivedEpisode] {
        var items: [ArchivedEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                guard let at = archivedAtById[episode.id] else { continue }
                items.append(
                    ArchivedEpisode(
                        episode: episode,
                        feedTitle: displayTitle(for: feed),
                        archivedAtEpochMs: at
                    )
                )
            }
        }
        var knownIds = Set(items.map(\.id))
        for episode in queue where !knownIds.contains(episode.id) {
            guard let at = archivedAtById[episode.id] else { continue }
            let title = displayTitle(containingEpisodeId: episode.id)
            items.append(
                ArchivedEpisode(
                    episode: episode,
                    feedTitle: title,
                    archivedAtEpochMs: at
                )
            )
            knownIds.insert(episode.id)
        }
        // Channel podcast:trailer archived from the player. Same synthetic id as
        // playback; not stored in feed.episodes, so the loops above miss it and
        // Archived stays empty while the player shows Restore.
        for (episodeId, at) in archivedAtById where !knownIds.contains(episodeId) {
            guard let resolved = trailerEpisodeForHistory(id: episodeId) else { continue }
            items.append(
                ArchivedEpisode(
                    episode: resolved.episode,
                    feedTitle: resolved.feedTitle,
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

    /// Update the optional note on an existing bookmark. Position and id stay unchanged.
    /// Trims and caps to `EpisodeBookmarkStore.maxNoteLength` (same as add). Empty note clears it.
    /// No-op when the bookmark is missing. Persists via `bookmarksByEpisodeId` didSet → `bookmarks.json`.
    func updateBookmarkNote(episodeId: String, bookmarkId: UUID, note: String) {
        guard var list = bookmarksByEpisodeId[episodeId] else { return }
        guard let idx = list.firstIndex(where: { $0.id == bookmarkId }) else { return }
        let trimmed = EpisodeBookmarkStore.trimNote(note)
        guard list[idx].note != trimmed else { return }
        list[idx].note = trimmed
        var map = bookmarksByEpisodeId
        map[episodeId] = list
        bookmarksByEpisodeId = map
    }

    /// Remove every bookmark for an episode.
    func clearBookmarks(for episodeId: String) {
        guard bookmarksByEpisodeId[episodeId] != nil else { return }
        var map = bookmarksByEpisodeId
        map.removeValue(forKey: episodeId)
        bookmarksByEpisodeId = map
    }

    /// Total bookmark entries across all episodes (sum of array lengths; 0 when the map is empty).
    /// Used by Settings → Library Clear all bookmarks (footnote / disabled / confirm count).
    var bookmarksCount: Int {
        bookmarksByEpisodeId.values.reduce(0) { $0 + $1.count }
    }

    /// Number of episodes that currently have at least one bookmark (map key count).
    /// Optional companion to `bookmarksCount` for “across N episodes” copy.
    var bookmarkedEpisodesCount: Int {
        bookmarksByEpisodeId.count
    }

    /// Remove every bookmark from `bookmarks.json` (same as emptying the whole map).
    /// Clears `bookmarksByEpisodeId` to `[:]`; persists via didSet.
    /// Does **not** touch chapters, Share with position, episode/feed private notes, favorites, archive, queue, downloads, or playback.
    /// Callers must confirm first (Settings → Library `confirmationDialog`).
    func clearAllBookmarks() {
        guard !bookmarksByEpisodeId.isEmpty else { return }
        bookmarksByEpisodeId = [:]
    }

    // MARK: - Episode private notes (local-only)

    /// Local-only private note for an episode, or `nil` when unset.
    func episodePrivateNote(for episodeId: String) -> String? {
        episodePrivateNotesById[episodeId]
    }

    /// Whether the episode has a non-empty local private note.
    func hasEpisodePrivateNote(for episodeId: String) -> Bool {
        episodePrivateNotesById[episodeId] != nil
    }

    /// Set or clear the local private note for an episode.
    /// Pass `nil` or empty (after normalize) to remove the key. Persists via didSet → `episode-notes.json`.
    func setEpisodePrivateNote(for episodeId: String, _ note: String?) {
        let normalized = EpisodePrivateNotes.normalized(note)
        var map = episodePrivateNotesById
        if let normalized {
            map[episodeId] = normalized
        } else {
            map.removeValue(forKey: episodeId)
        }
        episodePrivateNotesById = map
    }

    /// Remove every episode private note from `episode-notes.json` (same as per-episode Clear → nil).
    /// Clears the whole `episodePrivateNotesById` map; persists via didSet.
    /// Does **not** touch feed private notes, bookmarks, favorites, archive, queue, downloads, or playback.
    /// Callers must confirm first (Settings → Library `confirmationDialog`).
    func clearAllEpisodePrivateNotes() {
        guard !episodePrivateNotesById.isEmpty else { return }
        episodePrivateNotesById = [:]
    }

    /// Number of `feedSettingsById` entries that currently have a non-nil `privateNote`.
    /// Used by Settings → Library Clear all feed private notes (footnote / disabled / confirm count).
    var feedPrivateNotesCount: Int {
        feedSettingsById.values.reduce(into: 0) { count, settings in
            if settings.privateNote != nil { count += 1 }
        }
    }

    /// Clears `FeedSettings.privateNote` for every map entry that has one.
    /// Mutates `feedSettingsById` once (single `feed-settings.json` persist) — same batch spirit as `unpinAll()`.
    /// When settings become `.isDefault` after clearing the note, removes the map entry (same as unpinAll).
    /// Does **not** touch episode private notes, bookmarks, pin, tags, favorites, archive, queue, downloads, or playback.
    /// Callers must confirm first (Settings → Library `confirmationDialog`).
    /// - Returns: number of feed notes cleared (entries that had a non-nil `privateNote`).
    @discardableResult
    func clearAllFeedPrivateNotes() -> Int {
        let noteIds = feedSettingsById.compactMap { feedId, settings -> UUID? in
            settings.privateNote != nil ? feedId : nil
        }
        guard !noteIds.isEmpty else { return 0 }
        var next = feedSettingsById
        for feedId in noteIds {
            guard var settings = next[feedId], settings.privateNote != nil else { continue }
            settings.privateNote = nil
            if settings.isDefault {
                next.removeValue(forKey: feedId)
            } else {
                next[feedId] = settings
            }
        }
        feedSettingsById = next
        return noteIds.count
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

    /// Archive every non-archived episode in the full Favorites catalog (bulk).
    /// Uses store `favoriteEpisodes` order (**newest-first** by `favoritedAtEpochMs`) and ignores
    /// podcast, search, and sort filters. Writes `archivedAtById` once, preserving existing archive
    /// timestamps for any already-archived ids. Callers must confirm first.
    func archiveAllFavorites() {
        let ids = favoriteEpisodes
            .map(\.episode.id)
            .filter { !isArchived($0) }
        guard !ids.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
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

    /// Append unplayed, non-archived, not-already-queued episodes from the full Favorites catalog.
    /// Uses `favoriteEpisodes` order (newest favorited first), not the UI podcast, search, or sort
    /// filters. This follows the same eligibility policy as All Episodes / Feed detail: played,
    /// archived, and already-queued episodes are skipped. Uses `enqueue` (append), not `playNext`,
    /// and remains allowed while the queue lock is on.
    /// Callers must confirm first (Favorites toolbar `confirmationDialog`).
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllUnplayedFavorites() -> Int {
        let candidates = enqueueAllUnplayedFavoritesCandidates()
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Eligible episodes for Favorites **Add all unplayed to queue**. Shared by the confirmation
    /// count and `enqueueAllUnplayedFavorites`; the catalog is always the full Favorites catalog.
    func enqueueAllUnplayedFavoritesCandidates() -> [PodcastEpisode] {
        favoriteEpisodes
            .map(\.episode)
            .filter { episode in
                !isPlayed(episode.id) && !isArchived(episode.id) && !isInQueue(episode.id)
            }
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

    /// Append unplayed, non-archived, not-already-queued episodes from the full completed
    /// Downloads catalog. Uses DownloadService.downloads catalog order (oldest completed first),
    /// not the Downloads UI chip, podcast, search, or sort filters. Played, archived, and already
    /// queued episodes are skipped. Safe while queue lock is on; callers must confirm first.
    /// Requires downloads to be wired on the store; returns 0 if unset.
    /// - Returns: number of episodes newly appended.
    @discardableResult
    func enqueueAllUnplayedDownloads() -> Int {
        let candidates = enqueueAllUnplayedDownloadsCandidates()
        for episode in candidates {
            enqueue(episode)
        }
        return candidates.count
    }

    /// Eligible episodes for Downloads **Add all unplayed to queue**. Shared by the confirmation
    /// count and enqueue action; the catalog is always the full completed Downloads catalog.
    func enqueueAllUnplayedDownloadsCandidates() -> [PodcastEpisode] {
        guard let downloads else { return [] }
        return downloads.downloads
            .map(\.episode)
            .filter { episode in
                !isPlayed(episode.id) && !isArchived(episode.id) && !isInQueue(episode.id)
            }
    }

    /// Starred episodes across feeds, newest favorited first.
    /// Also includes a starred channel trailer (synthetic id, not in `feed.episodes`)
    /// and queue-only copies.
    var favoriteEpisodes: [FavoriteEpisode] {
        var items: [FavoriteEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                guard let at = favoriteAtById[episode.id] else { continue }
                items.append(
                    FavoriteEpisode(
                        episode: episode,
                        feedTitle: displayTitle(for: feed),
                        favoritedAtEpochMs: at
                    )
                )
            }
        }
        // Queue-only copies that were starred (rare).
        var knownIds = Set(items.map(\.id))
        for episode in queue where !knownIds.contains(episode.id) {
            guard let at = favoriteAtById[episode.id] else { continue }
            let title = displayTitle(containingEpisodeId: episode.id)
            items.append(
                FavoriteEpisode(
                    episode: episode,
                    feedTitle: title,
                    favoritedAtEpochMs: at
                )
            )
            knownIds.insert(episode.id)
        }
        // Channel podcast:trailer starred from the player. Same synthetic id as
        // playback; not stored in feed.episodes, so the loops above miss it and
        // Favorites stays empty while the player star stays on.
        for (episodeId, at) in favoriteAtById where !knownIds.contains(episodeId) {
            guard let resolved = trailerEpisodeForHistory(id: episodeId) else { continue }
            items.append(
                FavoriteEpisode(
                    episode: resolved.episode,
                    feedTitle: resolved.feedTitle,
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
        // Home reads this six times per body (directly and via `continueListeningEpisodes`),
        // and Home reruns on every 0.5s playback tick. Rebuild only when an input below changes.
        if let cached = historyEpisodesCache {
            return cached
        }
        let built = buildHistoryEpisodes()
        historyEpisodesCache = built
        return built
    }

    /// Last `historyEpisodes` result. Inputs: `feeds` (episodes, trailers, containing feed),
    /// `queue` (queue-only copies), `playbackStates`, `feedSettingsById` (`displayTitle`).
    /// Each one's observer clears this.
    private var historyEpisodesCache: [HistoryEpisode]?

    private func buildHistoryEpisodes() -> [HistoryEpisode] {
        var items: [HistoryEpisode] = []
        for feed in feeds {
            for episode in feed.episodes {
                let state = playbackState(for: episode.id)
                guard state.belongsInHistory else { continue }
                let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
                items.append(
                    HistoryEpisode(
                        episode: episode,
                        feedTitle: displayTitle(for: feed),
                        lastPlayedAtEpochMs: lastPlayed
                    )
                )
            }
        }
        // Include queue-only copies that still have playback state (rare but possible).
        var knownIds = Set(items.map(\.id))
        for episode in queue where !knownIds.contains(episode.id) {
            let state = playbackState(for: episode.id)
            guard state.belongsInHistory else { continue }
            let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
            let title = displayTitle(containingEpisodeId: episode.id)
            items.append(
                HistoryEpisode(
                    episode: episode,
                    feedTitle: title,
                    lastPlayedAtEpochMs: lastPlayed
                )
            )
            knownIds.insert(episode.id)
        }
        // Channel podcast:trailer playback uses a synthetic id and is not stored in
        // feed.episodes. Without this, playing a trailer never shows up in History
        // even though playback.json has the progress. Rebuild from the feed trailer
        // list (same id PlaybackService.play used).
        for (episodeId, state) in playbackStates where !knownIds.contains(episodeId) {
            guard state.belongsInHistory else { continue }
            guard let resolved = trailerEpisodeForHistory(id: episodeId) else { continue }
            let lastPlayed = state.lastPlayedAtEpochMs ?? state.updatedAtEpochMs
            items.append(
                HistoryEpisode(
                    episode: resolved.episode,
                    feedTitle: resolved.feedTitle,
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


    /// Rebuild a channel `podcast:trailer` episode from its synthetic playback id.
    /// Id shape matches `PodcastTrailer.asPlaybackEpisode`: `podcast-trailer:<feedUUID>:<mediaURL>`.
    /// Returns nil when the feed or trailer is gone — no invented episode.
    private func trailerEpisodeForHistory(id: String) -> (episode: PodcastEpisode, feedTitle: String)? {
        guard id.hasPrefix("podcast-trailer:") else { return nil }
        let parts = id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, let feedId = UUID(uuidString: String(parts[1])) else { return nil }
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return nil }
        for trailer in feed.trailers {
            guard let episode = trailer.asPlaybackEpisode(feedId: feedId), episode.id == id else { continue }
            return (episode, displayTitle(for: feed))
        }
        return nil
    }

    /// Drop progress / played flags so the episode leaves History (episode row itself stays).
    func removeFromHistory(_ episodeId: String) {
        playbackStates.removeValue(forKey: episodeId)
        pendingAutoDeleteIds.remove(episodeId)
        // Continue listening is derived from this playback entry. Queue didSet is not
        // involved, so the homescreen widget / Watch snapshot must be republished here.
        publishWidgetSnapshot()
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
        // Same as per-row Remove: playback.json changed without a queue write, so
        // Continue listening (widget / Watch) would otherwise keep the cleared episode.
        publishWidgetSnapshot()
    }

    /// Mark every unplayed, non-archived episode in the History catalog as played.
    /// Uses full `historyEpisodes` (newest-lastPlayed-first) — **not** podcast/search filter.
    /// IDs are snapshotted before calling `markPlayed` so per-episode side effects (including
    /// auto-delete-after-playing) still apply. Callers must confirm first.
    func markAllHistoryPlayed() {
        for id in markAllHistoryPlayedCandidateIds {
            markPlayed(id)
        }
    }

    /// Number of unplayed, non-archived episodes in the full History catalog.
    /// This intentionally ignores all History view filters.
    func markAllHistoryPlayedCandidateCount() -> Int {
        markAllHistoryPlayedCandidateIds.count
    }

    private var markAllHistoryPlayedCandidateIds: [String] {
        historyEpisodes
            .map(\.episode.id)
            .filter { !isPlayed($0) && !isArchived($0) }
    }

    /// Mark every **played** episode in the History catalog as unplayed (bulk).
    /// Uses full `historyEpisodes` (newest-lastPlayed-first) — **not** podcast/search filter.
    /// Eligible = `isPlayed` only (in-progress unplayed stay; same as per-row Mark unplayed).
    /// `markUnplayed` keeps progress; episodes leave History when no remaining progress
    /// (`belongsInHistory` = isPlayed || position > 1). Does **not** delete downloads,
    /// clear queue, unstar, or stop playback. Callers must confirm first.
    func markAllHistoryUnplayed() {
        let ids = historyEpisodes
            .map(\.episode.id)
            .filter { isPlayed($0) }
        for id in ids {
            markUnplayed(id)
        }
    }

    /// Archive every non-archived episode in the full History catalog (bulk).
    /// Uses store `historyEpisodes` order (**newest-first** by `lastPlayedAtEpochMs`) and ignores
    /// podcast, search, and sort filters. Writes `archivedAtById` once, preserving existing archive
    /// timestamps for any already-archived ids. Archiving is independent from played state and does
    /// not mark played, delete downloads, clear the queue, or remove History entries. Callers must
    /// confirm first (History toolbar `confirmationDialog`).
    func archiveAllHistory() {
        let ids = historyEpisodes
            .map(\.episode.id)
            .filter { !isArchived($0) }
        guard !ids.isEmpty else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var map = archivedAtById
        for id in ids {
            if map[id] == nil {
                map[id] = now
            }
        }
        archivedAtById = map
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
            // History size trim deletes playback state without a queue write.
            // Continue listening (widget / Watch) would otherwise keep the dropped episode.
            publishWidgetSnapshot()
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
                perFeed[feed.id] = (displayTitle(for: feed), feedPlayed, feedInProgress, feedSeconds)
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
                var entry = perFeed[feed.id] ?? (displayTitle(for: feed), 0, 0, 0)
                if state.isPlayed {
                    entry.played += 1
                } else {
                    entry.inProgress += 1
                }
                entry.seconds += secs
                perFeed[feed.id] = entry
            }
        }

        // Channel podcast:trailer progress is stored under a synthetic id and is not
        // in feed.episodes. History already shows it. Count the same playback.json row
        // when that trailer still exists; a removed trailer is not invented.
        var countedEpisodeIds = knownEpisodeIds
        for episode in queue {
            countedEpisodeIds.insert(episode.id)
        }
        for (episodeId, state) in playbackStates where !countedEpisodeIds.contains(episodeId) {
            guard include(state) else { continue }
            guard trailerEpisodeForHistory(id: episodeId) != nil else { continue }
            guard let feed = feed(containingEpisodeId: episodeId) else { continue }
            let secs = ListeningTimeEstimate.seconds(for: state)
            if state.isPlayed {
                played += 1
            } else {
                inProgress += 1
            }
            totalSeconds += secs
            var entry = perFeed[feed.id] ?? (displayTitle(for: feed), 0, 0, 0)
            if state.isPlayed {
                entry.played += 1
            } else {
                entry.inProgress += 1
            }
            entry.seconds += secs
            perFeed[feed.id] = entry
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
                consider(episodeId: episode.id, feedId: feed.id, feedTitle: displayTitle(for: feed))
            }
        }
        let knownEpisodeIds = Set(feeds.flatMap { $0.episodes.map(\.id) })
        for episode in queue where !knownEpisodeIds.contains(episode.id) {
            let feed = feed(containingEpisodeId: episode.id)
            consider(
                episodeId: episode.id,
                feedId: feed?.id,
                feedTitle: feed.map { displayTitle(for: $0) } ?? ""
            )
        }
        var countedEpisodeIds = knownEpisodeIds
        for episode in queue {
            countedEpisodeIds.insert(episode.id)
        }
        for episodeId in playbackStates.keys where !countedEpisodeIds.contains(episodeId) {
            guard trailerEpisodeForHistory(id: episodeId) != nil else { continue }
            guard let feed = feed(containingEpisodeId: episodeId) else { continue }
            consider(
                episodeId: episodeId,
                feedId: feed.id,
                feedTitle: displayTitle(for: feed)
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

        // Same catalog as the Favorites screen. A star whose episode is gone (local file
        // removed on rescan) stays in favorites.json but is not listed there.
        let listedFavorites = favoriteEpisodes
        var favoritesInRange = 0
        for item in listedFavorites {
            if inRange(item.favoritedAtEpochMs) {
                favoritesInRange += 1
            }
        }

        return EchoYearSummary(
            year: resolvedYear,
            playedEpisodeCount: played,
            approximateListenedSeconds: totalSeconds,
            topPodcasts: Array(top.prefix(10)),
            favoritesCountThisYear: favoritesInRange,
            favoritesTotalCount: listedFavorites.count
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

    /// Home / Inbox banner text for one podcast's refresh failure: names the podcast, since
    /// Refresh all keeps only the last failure and the system message does not say which feed.
    private func setRefreshError(_ message: String, feed: PodcastFeed) {
        lastError = String(
            format: String(localized: "Could not refresh %1$@: %2$@"),
            nonEmptyDisplayTitle(for: feed) ?? String(localized: "Unknown podcast"),
            message
        )
        lastErrorFeedId = feed.id
    }

    /// Drop the Home/Inbox banner only when this podcast is the one it names.
    /// A successful refresh of a different feed must not hide another podcast's failure.
    private func clearRefreshError(ifFeed feed: PodcastFeed) {
        if lastErrorFeedId == feed.id {
            lastError = nil
        }
    }

    private func beginLoadingOperation() {
        loadingOperationCount += 1
        isLoading = true
    }

    private func endLoadingOperation() {
        loadingOperationCount = max(0, loadingOperationCount - 1)
        if loadingOperationCount == 0 {
            isLoading = false
        }
    }

    private func beginDeferringFeedsSave() {
        feedsSaveDeferralDepth += 1
    }

    private func endDeferringFeedsSave() {
        feedsSaveDeferralDepth = max(0, feedsSaveDeferralDepth - 1)
        if feedsSaveDeferralDepth == 0 {
            flushDeferredFeedsSave()
        }
    }

    /// Write feeds.json now if a batch deferred it (also called when the app leaves the foreground).
    func flushDeferredFeedsSave() {
        guard feedsSaveIsPending else { return }
        feedsSaveIsPending = false
        PodcastPersistence.saveFeeds(feeds)
    }

    /// Refresh every subscribed feed (Inbox pull-to-refresh + auto Keep updated). Continues on per-feed errors.
    /// Publishes honest per-feed completion counts (`refreshCompletedCount` / `refreshTotalCount`) for UI.
    func refreshAllFeeds() async {
        // Second call while one runs (toolbar Refresh tapped twice, pull-to-refresh during the
        // launch auto-refresh) waits for it instead of starting another pass: both passes
        // snapshotted the same old episode ids, so new episodes were announced, queued, and
        // auto-downloaded twice.
        if isRefreshingAllFeeds {
            await withCheckedContinuation { continuation in
                refreshAllFeedsWaiters.append(continuation)
            }
            return
        }
        isRefreshingAllFeeds = true
        defer {
            isRefreshingAllFeeds = false
            let waiters = refreshAllFeedsWaiters
            refreshAllFeedsWaiters = []
            waiters.forEach { $0.resume() }
        }
        lastError = nil
        beginLoadingOperation()
        beginDeferringFeedsSave()
        defer {
            endLoadingOperation()
            refreshCompletedCount = 0
            refreshTotalCount = 0
            endDeferringFeedsSave()
        }
        let snapshot = feeds
        let targets = snapshot.filter {
            !$0.feedUrl.isEmpty && feedSettings(for: $0.id).participatesInBulkRefresh
        }
        refreshTotalCount = targets.count
        refreshCompletedCount = 0
        var newBatches: [NewEpisodeBatch] = []
        for feed in targets {
            // Unsubscribed while this refresh was running: do not fetch it back in.
            guard feeds.contains(where: { $0.id == feed.id }) else {
                refreshCompletedCount += 1
                continue
            }
            if LocalFolderFeed.isLocalFolderFeed(feed) {
                let existingIds = Set(feed.episodes.map(\.id))
                do {
                    let updated = try rescanLocalFolderFeed(feed)
                    let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
                    if !newcomers.isEmpty {
                        newBatches.append(
                            NewEpisodeBatch(
                                feedTitle: displayTitle(for: updated),
                                feedId: updated.id,
                                feedUrl: updated.feedUrl,
                                episodes: newcomers
                            )
                        )
                    }
                } catch {
                    setRefreshError(error.localizedDescription, feed: feed)
                }
                refreshCompletedCount += 1
                continue
            }
            do {
                let newcomers = try await subscribeQuietly(feedUrl: feed.feedUrl, onlyIfSubscribed: true)
                if let updated = feeds.first(where: { $0.feedUrl == feed.feedUrl }) {
                    if !newcomers.isEmpty {
                        newBatches.append(
                            NewEpisodeBatch(
                                feedTitle: displayTitle(for: updated),
                                feedId: updated.id,
                                feedUrl: updated.feedUrl,
                                episodes: newcomers
                            )
                        )
                    }
                }
            } catch {
                setRefreshError(error.localizedDescription, feed: feed)
            }
            refreshCompletedCount += 1
        }
        // Stamp even if some feeds failed — avoids hammering on every foreground.
        settings?.markFeedRefreshCompleted()
        // A podcast unsubscribed after its turn must not get a banner, queue items, or downloads.
        newBatches = newBatches.filter { batch in
            feeds.contains(where: { $0.id == batch.feedId })
        }
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

    /// Matching subscriptions by display title (customTitle ?? RSS), optional descriptionText, author, language, categories, or local private note (case-insensitive).
    /// Description uses shownote plain text (same strip as the description sheet), not raw HTML tags/entities.
    /// Does **not** search bookmark notes / chapters / transcripts.
    func matchingFeeds(query: String) -> [PodcastFeed] {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }
        return feeds.filter { feed in
            let shown = displayTitle(for: feed)
            return Self.matches(shown, query: q)
                || Self.matches(feed.title, query: q)
                || Self.matchesDescription(feed.descriptionText, query: q)
                || Self.matches(feed.author, query: q)
                || Self.matches(feed.language, query: q)
                || Self.matches(feed.displayLanguage, query: q)
                || feed.displayCategories.contains(where: { Self.matches($0, query: q) })
                || Self.matches(feedSettings(for: feed.id).privateNote, query: q)
        }
        .sorted {
            displayTitle(for: $0).localizedCaseInsensitiveCompare(displayTitle(for: $1)) == .orderedAscending
        }
    }

    /// Whether an episode matches local library / Feed detail search (title, optional descriptionText, private note, any bookmark note).
    /// Description uses shownote plain text so `Rock & Roll` matches stored `Rock &amp; Roll` and tag-only tokens do not.
    /// Empty / whitespace-only query → false. Does **not** search chapters / transcripts. Empty bookmark notes ignored.
    func episodeMatchesLibraryQuery(_ episode: PodcastEpisode, query: String) -> Bool {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return false }
        return Self.matches(episode.title, query: q)
            || Self.matchesDescription(episode.descriptionText, query: q)
            || Self.matches(episodePrivateNote(for: episode.id), query: q)
            || bookmarks(for: episode.id).contains(where: { Self.matches($0.note, query: q) })
    }

    /// Matching episodes across subscriptions by episode title, optional descriptionText, local private note, or any bookmark note (feeds listed separately).
    /// Does **not** search chapters / transcripts. Empty bookmark notes are ignored. Episode appears once if any field matches.
    func matchingEpisodes(query: String) -> [LibraryEpisodeHit] {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }
        var hits: [LibraryEpisodeHit] = []
        for feed in feeds {
            for episode in feed.episodes where episodeMatchesLibraryQuery(episode, query: q) {
                hits.append(
                    LibraryEpisodeHit(
                        episode: episode,
                        feedTitle: displayTitle(for: feed),
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
        return value.localizedSearchContains(query)
    }

    /// Shownotes / feed description are stored as HTML. Match the same plain text the sheets show
    /// (`HTMLTextStripping`) so entities decode and tags are not searchable.
    private static func matchesDescription(_ value: String?, query: String) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let plain = HTMLTextStripping.plainText(from: value)
        guard !plain.isEmpty else { return false }
        return plain.localizedSearchContains(query)
    }

    // MARK: - Local folder feeds (beta)

    /// Subscribe to a user-picked folder: persist security-scoped bookmark + synthetic feed.
    /// Call while the picker URL still has security-scoped access (`fileImporter`).
    /// Throws `alreadySubscribed` when the same folder path is already a local-folder feed.
    /// Leaves the shared `lastError` alone (same as URL `subscribe`): Add podcast shows folder
    /// errors in its own `folderError`; clearing here wiped a Home/Inbox refresh banner.
    @discardableResult
    func subscribeLocalFolder(folderURL: URL) throws -> PodcastFeed {
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
    @discardableResult
    func refreshLocalFolderFeed(_ feed: PodcastFeed) async -> String? {
        // Same as refresh(_:): do not wipe another podcast's Home/Inbox banner at start.
        beginLoadingOperation()
        defer { endLoadingOperation() }
        let existingIds = Set(feed.episodes.map(\.id))
        do {
            let updated = try rescanLocalFolderFeed(feed)
            let newcomers = updated.episodes.filter { !existingIds.contains($0.id) }
            var newBatches: [NewEpisodeBatch] = []
            if !newcomers.isEmpty {
                newBatches = [
                    NewEpisodeBatch(
                        feedTitle: displayTitle(for: updated),
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
            clearRefreshError(ifFeed: feed)
        } catch {
            setRefreshError(error.localizedDescription, feed: feed)
            return error.localizedDescription
        }
        return nil
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
        syncStoredEpisodeCopies(with: updated)
        return updated
    }

    // MARK: - OPML import / export

    func exportOpmlXML() -> String {
        OpmlWriter.writeDocument(feeds: feeds, titleForFeed: { displayTitle(for: $0) })
    }

    func exportOpmlTemporaryFile() throws -> URL {
        try OpmlWriter.writeTemporaryFile(feeds: feeds, titleForFeed: { displayTitle(for: $0) })
    }

    /// Feeds written to OPML / HTML export (excludes empty URLs and local folder feeds).
    var exportableSubscriptionCount: Int {
        feeds.filter { !$0.feedUrl.isEmpty && !LocalFolderFeed.isLocalFolderFeed($0) }.count
    }

    func exportOpmlData() throws -> Data {
        let xml = OpmlWriter.writeDocument(feeds: feeds, titleForFeed: { displayTitle(for: $0) })
        guard let data = xml.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    // MARK: - HTML export (subscriptions)

    func exportSubscriptionsHTML(includeEpisodeCount: Bool = true) -> String {
        HtmlExportWriter.writeDocument(feeds: feeds, includeEpisodeCount: includeEpisodeCount, titleForFeed: { displayTitle(for: $0) })
    }

    func exportSubscriptionsHTMLTemporaryFile(includeEpisodeCount: Bool = true) throws -> URL {
        try HtmlExportWriter.writeTemporaryFile(feeds: feeds, includeEpisodeCount: includeEpisodeCount, titleForFeed: { displayTitle(for: $0) })
    }

    /// Parse OPML and subscribe each feed URL via the existing fetch/parse pipeline.
    /// Skips URLs already in `feeds`. Records per-URL errors without aborting the batch.
    ///
    /// Already-subscribed uses `FeedURLNormalization.canonicalKey` (http↔https, trailing slash)
    /// plus a full lowercase, so `https://host/feed` and `http://host/feed/` are one subscription.
    /// The stored feed URL is not rewritten when an outline is skipped.
    func importOpml(data: Data, sourceFileName: String? = nil) async {
        opmlImportError = nil
        beginDeferringFeedsSave()
        defer { endDeferringFeedsSave() }
        var state = OpmlImportState(isImporting: true, sourceFileName: sourceFileName)
        opmlImport = state
        do {
            let outlines = try OpmlReader.parse(data: data)
            // Deduplicate by canonical feed URL (first wins). Lowercase keeps path/query
            // case-insensitive, matching the previous full-string compare.
            var seen = Set<String>()
            var unique: [OpmlOutline] = []
            for o in outlines {
                let key = Self.opmlSubscriptionKey(o.xmlUrl)
                if seen.insert(key).inserted {
                    unique.append(o)
                }
            }
            state.total = unique.count
            opmlImport = state
            var subscribed = Set(feeds.map { Self.opmlSubscriptionKey($0.feedUrl) })

            for outline in unique {
                state.currentTitle = outline.text
                opmlImport = state
                let urlKey = Self.opmlSubscriptionKey(outline.xmlUrl)
                if subscribed.contains(urlKey) {
                    state.skipped += 1
                    state.completed += 1
                    opmlImport = state
                    continue
                }
                do {
                    // An `itpc://` outline is stored (and exported) as https; others unchanged.
                    try await subscribeQuietly(feedUrl: FeedURLNormalization.storedFeedURL(outline.xmlUrl))
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
            opmlImportError = error.localizedDescription
        }
        state.currentTitle = nil
        state.isImporting = false
        opmlImport = state
    }

    /// OPML duplicate key: Add-sheet canonical URL (scheme and trailing slash) and case.
    private static func opmlSubscriptionKey(_ feedUrl: String) -> String {
        FeedURLNormalization.canonicalKey(feedUrl).lowercased()
    }

    /// Subscribe without flipping the global `isLoading` overlay (used by OPML batch / refresh).
    /// Loads Keychain credentials for an existing subscription when `credentials` is nil.
    /// When `persistCredentials` is true and credentials are usable, saves them under the feed id
    /// (never into `feed-settings.json`). Passwords are never logged.
    /// Returns the refreshed episodes whose ids the stored feed did not have at merge time
    /// (empty for a new subscription). Taken at merge, not before the fetch, so a per-feed
    /// refresh overlapping refresh-all of the same feed reports each new episode only once.
    @discardableResult
    func subscribeQuietly(
        feedUrl: String,
        credentials: FeedHttpBasicCredentials? = nil,
        persistCredentials: Bool = false,
        onlyIfSubscribed: Bool = false
    ) async throws -> [PodcastEpisode] {
        var newcomers: [PodcastEpisode] = []
        let resolvedCreds = credentials ?? httpBasicCredentials(forFeedUrl: feedUrl)
        var feed = try await repository.fetchAndParse(feedUrl: feedUrl, credentials: resolvedCreds)
        feed.feedUrl = feedUrl
        // Stamp only on successful network fetch+parse. Failed refresh throws before this
        // and leaves any previous `lastRefreshedAtEpochMs` untouched. Local-folder feeds
        // never go through this path (Rescan is not a network refresh — leave nil / hide).
        feed.lastRefreshedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let index = feeds.firstIndex(where: { $0.feedUrl == feedUrl }) {
            feed.id = feeds[index].id // keep stable identity across refresh
            // Many feeds only list their newest items. An episode that left the RSS
            // would also leave Favorites, Archived, and History, which list feed.episodes.
            // Queue and Downloads keep their own copy, but resolve the podcast name,
            // artwork, and per-feed settings through feed.episodes.
            let storedIds = Set(feeds[index].episodes.map(\.id))
            newcomers = feed.episodes.filter { !storedIds.contains($0.id) }
            let freshIds = Set(feed.episodes.map(\.id))
            let kept = feeds[index].episodes.filter { episode in
                !freshIds.contains(episode.id) && (
                    isFavorite(episode.id)
                        || isArchived(episode.id)
                        || playbackState(for: episode.id).belongsInHistory
                        || isInQueue(episode.id)
                        || downloads?.isDownloaded(episode) == true
                )
            }
            feed.episodes.append(contentsOf: kept)
            feeds[index] = feed
        } else if onlyIfSubscribed {
            // Refresh all: the podcast was unsubscribed during the network fetch.
            return []
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
        // Serial → Oldest first once when per-feed episodeSort still nil (subscribe + refresh).
        applySerialOldestFirstHeuristicIfNeeded(for: feed)
        // Queue / Downloads (completed, waiting, in-flight) / loaded player keep pre-refresh
        // structs. Copy refreshed fields onto matching ids so Queue search, play, waiting
        // starts, and finished Downloads rows see the new title and URL.
        syncStoredEpisodeCopies(with: feed)
        return newcomers
    }

    /// After a successful refresh or local-folder rescan, copy refreshed episode fields onto
    /// stored copies that still use the same id. Does not reorder the queue, delete downloads,
    /// cancel in-flight transfers, seek, or rebuild the player item. Keeps already-loaded
    /// chapters when the new feed copy has none (lazy Podcast Index / media chapters are not
    /// in the RSS parse).
    private func syncStoredEpisodeCopies(with feed: PodcastFeed) {
        var byId: [String: PodcastEpisode] = [:]
        byId.reserveCapacity(feed.episodes.count)
        for episode in feed.episodes {
            byId[episode.id] = episode
        }
        guard !byId.isEmpty else { return }

        var nextQueue = queue
        var queueChanged = false
        for index in nextQueue.indices {
            let old = nextQueue[index]
            guard let fresh = byId[old.id] else { continue }
            let merged = Self.refreshedEpisode(fresh, replacing: old)
            guard merged != old else { continue }
            nextQueue[index] = merged
            queueChanged = true
        }
        if queueChanged {
            queue = nextQueue
        }

        downloads?.replaceEpisodeSnapshots(with: byId)

        if let current = playback?.currentEpisode, let fresh = byId[current.id] {
            let merged = Self.refreshedEpisode(fresh, replacing: current)
            playback?.replaceCurrentEpisodeMetadata(with: merged)
        }
    }

    /// Feed copy wins, except empty chapters keep a non-empty local list (lazy fetch).
    private static func refreshedEpisode(_ fresh: PodcastEpisode, replacing old: PodcastEpisode) -> PodcastEpisode {
        var merged = fresh
        if merged.chapters.isEmpty, !old.chapters.isEmpty {
            merged.chapters = old.chapters
        }
        return merged
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

