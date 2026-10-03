import SwiftUI

/// Landing tab: honest previews driven by Settings → Home layout (order + visibility).
/// Toolbar **Configure Home** opens the same layout editor (Android `configure_home` parity).
/// `.searchable` filters visible section episode previews via `episodeMatchesLibraryQuery` (title /
/// descriptionText / private note / bookmark notes) + feed title, and Recently updated feed cards by
/// display title only; empty sections hide while filtering. **Not** chapters / transcripts.
/// Optional **History** / **Archived** / **Favorites** / **Downloads** previews (off by default) soft-cap like Continue.
struct HomeView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var parental: ParentalControls
    @EnvironmentObject private var downloads: DownloadService
    @Binding var selectedTab: RootTab
    @State private var showDiscoverPINGate = false
    @State private var navigateToDiscover = false
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    /// Soft-cap for episode-list Home previews (Continue / Inbox / Queue / Favorites / History /
    /// Archived / Downloads). From `AppSettings.homePreviewLimit` (3/5/8/10, default 5); clamp to
    /// the allowed preset set if UserDefaults holds an unexpected value. Discover charts preview
    /// uses `homeDiscoverPreviewLimit`; full TopListsView uses `AppSettings.discoverChartsLimit`.
    private var previewLimit: Int {
        let allowed = Set(HomePreviewLimit.allCases.map(\.rawValue))
        let raw = settings.homePreviewLimit.rawValue
        return allowed.contains(raw) ? raw : HomePreviewLimit.five.rawValue
    }

    /// Soft-cap for Home **Recently updated** feed cards. From `AppSettings.homeFeedsPreviewLimit`
    /// (same 3/5/8/10 presets, default 5); clamp to the allowed preset set. Does **not** affect
    /// Discover charts preview (`homeDiscoverPreviewLimit`) / full Top lists or episode-list `previewLimit`.
    private var feedsLimit: Int {
        let allowed = Set(HomePreviewLimit.allCases.map(\.rawValue))
        let raw = settings.homeFeedsPreviewLimit.rawValue
        return allowed.contains(raw) ? raw : HomePreviewLimit.five.rawValue
    }
    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var isSearchFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Continue preview: filter full continue catalog by library query + feed title, then cap
    /// (matches while searching beyond first `previewLimit`).
    private var continueItems: [HistoryEpisode] {
        Array(filterEpisodes(store.continueListeningEpisodes).prefix(previewLimit))
    }

    private var inboxItems: [InboxEpisode] {
        Array(filterEpisodes(store.inboxEpisodes).prefix(previewLimit))
    }

    /// Queue preview catalog after Home library-query + feed-title search filter (before soft-cap).
    /// Same fields as Queue tab: `episodeMatchesLibraryQuery` + `displayTitle(containingEpisodeId:)`.
    /// Does **not** follow Queue tab chips (`queueFilter`) — Home uses full queue order.
    private var filteredQueueCatalog: [PodcastEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.queue
        if q.isEmpty { return base }
        return base.filter { episode in
            if store.episodeMatchesLibraryQuery(episode, query: q) { return true }
            let feedTitle = store.displayTitle(containingEpisodeId: episode.id)
            return feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private var queueItems: [PodcastEpisode] {
        Array(filteredQueueCatalog.prefix(previewLimit))
    }

    private var recentFeeds: [PodcastFeed] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.recentlyUpdatedFeeds
        let filtered: [PodcastFeed]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { store.displayTitle(for: $0).localizedCaseInsensitiveContains(q) }
        }
        return Array(filtered.prefix(feedsLimit))
    }

    private var favoriteItems: [FavoriteEpisode] {
        Array(filterEpisodes(store.favoriteEpisodes).prefix(previewLimit))
    }

    /// History Home preview: newest last-played first (`historyEpisodes`). Does **not** follow
    /// History `historySort` / `historyPodcastFilter` — Home stays newest-lastPlayed-first.
    /// Distinct from Continue (in-progress-only): includes played + in-progress.
    private var historyItems: [HistoryEpisode] {
        Array(filterEpisodes(store.historyEpisodes).prefix(previewLimit))
    }

    /// Archived Home preview: newest archived first (`archivedEpisodes` / `archivedAtEpochMs`).
    /// Does **not** follow Archived `archivedSort` / `archivedPodcastFilter` — Home stays
    /// newest-archived-first store order.
    private var archivedItems: [ArchivedEpisode] {
        Array(filterEpisodes(store.archivedEpisodes).prefix(previewLimit))
    }

    /// Downloads Home preview catalog: newest completed first (`downloadedAtEpochMs`, else
    /// `pubDateEpochMs` / id tiebreak). Does **not** follow Downloads tab chips (`downloadsFilter` /
    /// `downloadsPodcastFilter`) or `downloadsSort` — Home stays newest-completed-first.
    private var downloadsCatalogNewestFirst: [DownloadedEpisode] {
        downloads.downloads.sorted { lhs, rhs in
            let l = lhs.downloadsSortEpochMs ?? Int64.min
            let r = rhs.downloadsSortEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.episode.id < rhs.episode.id
        }
    }

    /// Library-query + feed-title filter over full newest-completed catalog (before soft-cap).
    /// Same fields as Downloads tab: `episodeMatchesLibraryQuery` + `displayTitle(containingEpisodeId:)`.
    private var filteredDownloadsCatalog: [DownloadedEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = downloadsCatalogNewestFirst
        if q.isEmpty { return base }
        return base.filter { item in
            if store.episodeMatchesLibraryQuery(item.episode, query: q) { return true }
            let feedTitle = store.displayTitle(containingEpisodeId: item.episode.id)
            return feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private var downloadItems: [DownloadedEpisode] {
        Array(filteredDownloadsCatalog.prefix(previewLimit))
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Continue preview**
    /// rows only (`continueItems` = filter then soft-cap `previewLimit`). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes full
    /// duration; **played** (not current) → 0 (Continue catalog is already in-progress-only —
    /// still handled for honesty); **unknown duration skipped** (tilde when any skipped).
    /// Currently playing uses live `PlaybackService` position/duration. Wall-clock by default;
    /// optional Remaining time respects speed ÷ feed/default speed ≥0.5 (estimate, not the
    /// live session rate and not Volume boost).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `continueListeningEpisodes`
    /// catalog / History list.
    private var continueRemainingInfoLabel: String? {
        guard !continueItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: continueRemainingSummary)
    }

    private var continueRemainingAccessibilityLabel: String {
        guard let label = continueRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Continue listening remaining time \(label)")]
        let unknown = continueRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered continue catalog longer than visible preview rows.
        let filteredCatalogCount = filterEpisodes(store.continueListeningEpisodes).count
        if filteredCatalogCount > continueItems.count {
            parts.append(
                String(
                    localized: "Home Continue remaining time covers the preview only (first \(previewLimit)), not the full continue catalog"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home Continue remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// Continue preview only — not the full continue catalog, the History list,
    /// the other Home previews, or the full-screen remaining bars.
    private var continueRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home Continue listening bar sums the visible preview rows only. Those rows are in-progress episodes that are not marked played and already have more than one second of progress, newest last played first (last played time, otherwise the playback updated time, title A–Z when the time matches). Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full continue-listening catalog. It does not follow the History sort or the History podcast filter, and it is not the History list. The continue catalog comes from the stored History set, which already follows the History size limit, and this bar does not bring trimmed episodes back. Archiving does not by itself remove an in-progress episode from this preview. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home Continue listening bar sums the visible preview rows only. Those rows are in-progress episodes that are not marked played and already have more than one second of progress, newest last played first (last played time, otherwise the playback updated time, title A–Z when the time matches). Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full continue-listening catalog. It does not follow the History sort or the History podcast filter, and it is not the History list. The continue catalog comes from the stored History set, which already follows the History size limit, and this bar does not bring trimmed episodes back. Archiving does not by itself remove an in-progress episode from this preview. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var continueRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: continueItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Inbox/New preview**
    /// rows only (`inboxItems` = filter then soft-cap `previewLimit`). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes full
    /// duration; **played** (not current) → 0 (Inbox preview is usually unplayed-only — still
    /// handled for honesty); **unknown duration skipped** (tilde when any skipped).
    /// Currently playing uses live `PlaybackService` position/duration. Wall-clock by default;
    /// optional Remaining time respects speed ÷ feed/default speed ≥0.5 (estimate, not the
    /// live session rate and not Volume boost).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `inboxEpisodes` catalog / Inbox
    /// tab / tab badge.
    private var inboxRemainingInfoLabel: String? {
        guard !inboxItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: inboxRemainingSummary)
    }

    private var inboxRemainingAccessibilityLabel: String {
        guard let label = inboxRemainingInfoLabel else { return "" }
        var parts = [String(localized: "New / Inbox remaining time \(label)")]
        let unknown = inboxRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered inbox catalog longer than visible preview rows.
        let filteredCatalogCount = filterEpisodes(store.inboxEpisodes).count
        if filteredCatalogCount > inboxItems.count {
            parts.append(
                String(
                    localized: "Home Inbox remaining time covers the preview only (first \(previewLimit)), not the full Inbox"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home New / Inbox remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// New / Inbox preview only — not the full Inbox, the Inbox tab badge,
    /// the other Home previews, or the full-screen remaining bars.
    private var inboxRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home New or Inbox bar sums the visible preview rows only. Those rows are unplayed episodes that are not archived, including in-progress episodes, newest published first (publication date, title A–Z when the date matches). Episodes with no publication date come last. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Inbox and not the Inbox tab badge. It does not follow the Inbox sort, the Inbox podcast filter, or the Inbox episode type, and it is not the Inbox list. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Home Continue listening preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home New or Inbox bar sums the visible preview rows only. Those rows are unplayed episodes that are not archived, including in-progress episodes, newest published first (publication date, title A–Z when the date matches). Episodes with no publication date come last. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Inbox and not the Inbox tab badge. It does not follow the Inbox sort, the Inbox podcast filter, or the Inbox episode type, and it is not the Inbox list. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Home Continue listening preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var inboxRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: inboxItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Queue preview**
    /// rows only (`queueItems` = title/feed filter then soft-cap `previewLimit`). Remaining per
    /// episode = `max(0, duration − position)` when duration known; unplayed with duration
    /// contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService`
    /// position/duration. Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `store.queue` / Queue tab /
    /// tab badge / Queue screen chip+search filter.
    private var queueRemainingInfoLabel: String? {
        guard !queueItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: queueRemainingSummary)
    }

    private var queueRemainingAccessibilityLabel: String {
        guard let label = queueRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Home Queue remaining time \(label)")]
        let unknown = queueRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered queue catalog longer than visible preview rows.
        let filteredCatalogCount = filteredQueueCatalog.count
        if filteredCatalogCount > queueItems.count {
            parts.append(
                String(
                    localized: "Home Queue remaining time covers the preview only (first \(previewLimit)), not the full Queue"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home Queue remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// Queue preview only — not the full Queue, the Queue tab badge,
    /// the other Home previews, or the full-screen remaining bars.
    private var queueRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home Queue bar sums the visible preview rows only. Those rows follow the stored queue order. It does not follow the Queue played-status chip (All, Unplayed, or Played) or the Queue podcast filter, and it is not the Queue list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Queue, not the Queue tab, and not the Queue tab badge. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home Queue bar sums the visible preview rows only. Those rows follow the stored queue order. It does not follow the Queue played-status chip (All, Unplayed, or Played) or the Queue podcast filter, and it is not the Queue list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Queue, not the Queue tab, and not the Queue tab badge. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var queueRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: queueItems,
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Favorites preview**
    /// rows only (`favoriteItems` = filter then soft-cap `previewLimit`). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes full
    /// duration; **played** (not current) → 0; **unknown duration skipped** (tilde when any
    /// skipped). Currently playing uses live `PlaybackService` position/duration. Wall-clock only
    /// (no playback-speed divide by default; optional Remaining time respects speed).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `favoriteEpisodes` catalog /
    /// Favorites screen sort+search filter / Clear favorites count.
    /// Preview stays newest-favorited-first (does **not** follow Favorites `favoritesSort`).
    private var favoritesRemainingInfoLabel: String? {
        guard !favoriteItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: favoritesRemainingSummary)
    }

    private var favoritesRemainingAccessibilityLabel: String {
        guard let label = favoritesRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Home Favorites remaining time \(label)")]
        let unknown = favoritesRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered favorites catalog longer than visible preview rows.
        let filteredCatalogCount = filterEpisodes(store.favoriteEpisodes).count
        if filteredCatalogCount > favoriteItems.count {
            parts.append(
                String(
                    localized: "Home Favorites remaining time covers the preview only (first \(previewLimit)), not the full Favorites list"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home Favorites remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// Favorites preview only — not the full Favorites list, the Clear favorites count,
    /// the other Home previews, or the full-screen remaining bars.
    private var favoritesRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home Favorites bar sums the visible preview rows only. Those rows are starred episodes, newest favorited first (favorited time, title A–Z when the time matches). A queue-only copy is included when it is starred and not already listed on a subscribed feed. It does not follow the Favorites sort or the Favorites podcast filter, and it is not the Favorites list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Favorites list and not the Clear favorites count. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home Favorites bar sums the visible preview rows only. Those rows are starred episodes, newest favorited first (favorited time, title A–Z when the time matches). A queue-only copy is included when it is starred and not already listed on a subscribed feed. It does not follow the Favorites sort or the Favorites podcast filter, and it is not the Favorites list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Favorites list and not the Clear favorites count. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var favoritesRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: favoriteItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible History preview**
    /// rows only (`historyItems` = filter then soft-cap `previewLimit`). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes full
    /// duration; **played** (not current) → 0; **unknown duration skipped** (tilde when any
    /// skipped). Currently playing uses live `PlaybackService` position/duration. Wall-clock only
    /// (no playback-speed divide by default; optional Remaining time respects speed).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `historyEpisodes` catalog /
    /// History screen podcast+sort+search filter / Clear history count.
    /// Preview stays newest-lastPlayed-first (does **not** follow History `historySort`).
    private var historyRemainingInfoLabel: String? {
        guard !historyItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: historyRemainingSummary)
    }

    private var historyRemainingAccessibilityLabel: String {
        guard let label = historyRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Home History remaining time \(label)")]
        let unknown = historyRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered history catalog longer than visible preview rows.
        let filteredCatalogCount = filterEpisodes(store.historyEpisodes).count
        if filteredCatalogCount > historyItems.count {
            parts.append(
                String(
                    localized: "Home History remaining time covers the preview only (first \(previewLimit)), not the full History list"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home History remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// History preview only — not the full History list, the Clear history count,
    /// the other Home previews, or the full-screen remaining bars.
    private var historyRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home History bar sums the visible preview rows only. Those rows are played or in-progress episodes (marked played, or more than one second of progress), newest last played first (last played time, otherwise the playback updated time, title A–Z when the time matches). A queue-only copy is included when it still has that playback state. This preview includes played episodes, unlike Continue listening, which is in-progress only. It does not follow the History sort or the History podcast filter, and it is not the History list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full History list and not the Clear history count. The catalog is the stored History set, which already follows the History size limit, and this bar does not bring trimmed episodes back. Archiving does not by itself remove an episode from this preview. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home History bar sums the visible preview rows only. Those rows are played or in-progress episodes (marked played, or more than one second of progress), newest last played first (last played time, otherwise the playback updated time, title A–Z when the time matches). A queue-only copy is included when it still has that playback state. This preview includes played episodes, unlike Continue listening, which is in-progress only. It does not follow the History sort or the History podcast filter, and it is not the History list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full History list and not the Clear history count. The catalog is the stored History set, which already follows the History size limit, and this bar does not bring trimmed episodes back. Archiving does not by itself remove an episode from this preview. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home Archived preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var historyRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: historyItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Archived preview**
    /// rows only (`archivedItems` = filter then soft-cap `previewLimit`). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes full
    /// duration; **played** (not current) → 0; **unknown duration skipped** (tilde when any
    /// skipped). Currently playing uses live `PlaybackService` position/duration. Wall-clock only
    /// (no playback-speed divide by default; optional Remaining time respects speed).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `archivedEpisodes` catalog /
    /// Archived screen podcast+sort+search filter / Restore all count.
    /// Preview stays newest-archived-first (does **not** follow Archived `archivedSort`).
    private var archivedRemainingInfoLabel: String? {
        guard !archivedItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: archivedRemainingSummary)
    }

    private var archivedRemainingAccessibilityLabel: String {
        guard let label = archivedRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Home Archived remaining time \(label)")]
        let unknown = archivedRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered archived catalog longer than visible preview rows.
        let filteredCatalogCount = filterEpisodes(store.archivedEpisodes).count
        if filteredCatalogCount > archivedItems.count {
            parts.append(
                String(
                    localized: "Home Archived remaining time covers the preview only (first \(previewLimit)), not the full Archived list"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home Archived remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// Archived preview only — not the full Archived list, the Restore all count,
    /// the other Home previews, or the full-screen remaining bars. Archive does
    /// not mean played.
    private var archivedRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home Archived bar sums the visible preview rows only. Those rows are archived episodes, newest archived first (archived time, title A–Z when the time matches). A queue-only copy is included when it is archived and not already listed on a subscribed feed. Archive does not mean played. It does not follow the Archived sort or the Archived podcast filter, and it is not the Archived list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Archived list and not the Restore all count. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home Archived bar sums the visible preview rows only. Those rows are archived episodes, newest archived first (archived time, title A–Z when the time matches). A queue-only copy is included when it is archived and not already listed on a subscribed feed. Archive does not mean played. It does not follow the Archived sort or the Archived podcast filter, and it is not the Archived list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Archived list and not the Restore all count. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Favorites preview, the Home Downloads preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var archivedRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: archivedItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Downloads preview**
    /// rows only (`downloadItems` = newest-completed + title/feed filter then soft-cap
    /// `previewLimit`). Remaining per episode = `max(0, duration − position)` when duration known;
    /// unplayed with duration contributes full duration; **played** (not current) → 0; **unknown
    /// duration skipped** (tilde when any skipped). Currently playing uses live `PlaybackService`
    /// position/duration. Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `DownloadService.downloads`
    /// catalog / Downloads tab chip+search filter / tab badge.
    /// Preview stays newest-completed-first (does **not** follow Downloads `downloadsSort` /
    /// chips).
    private var downloadsRemainingInfoLabel: String? {
        guard !downloadItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: downloadsRemainingSummary)
    }

    private var downloadsRemainingAccessibilityLabel: String {
        guard let label = downloadsRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Home Downloads remaining time \(label)")]
        let unknown = downloadsRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered downloads catalog longer than visible preview rows.
        if filteredDownloadsCatalog.count > downloadItems.count {
            parts.append(
                String(
                    localized: "Home Downloads remaining time covers the preview only (first \(previewLimit)), not the full Downloads list"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Home Downloads remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums the visible
    /// Downloads preview only — not the full Downloads list, Cancel all or
    /// Delete all, the other Home previews, or the full-screen remaining bars.
    private var downloadsRemainingAccessibilityHint: String {
        let limit = previewLimit
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Home Downloads bar sums the visible preview rows only. Those rows are completed downloads, newest completed first (download completion time, otherwise the publication date; episode id when the time matches). An episode with neither time comes last. It does not follow the Downloads played-status chip (All, Unplayed, or Played), the Downloads podcast filter, or the Downloads sort, and it is not the Downloads list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Downloads list, not the Downloads tab, and not the Downloads tab badge. It is not the full offline Downloads catalog behind Play random, Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Cancel all downloads, Delete played downloads, Delete all downloads, Copy downloads, or Share downloads. In-progress downloads are not in this preview. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Home Downloads bar sums the visible preview rows only. Those rows are completed downloads, newest completed first (download completion time, otherwise the publication date; episode id when the time matches). An episode with neither time comes last. It does not follow the Downloads played-status chip (All, Unplayed, or Played), the Downloads podcast filter, or the Downloads sort, and it is not the Downloads list. Home search, when set, keeps episodes whose title, description, episode private note, or bookmark note matches, or whose feed title matches. It does not search chapters or transcripts. Then it keeps at most the first \(limit) rows. When more episodes match, this is not the full Downloads list, not the Downloads tab, and not the Downloads tab badge. It is not the full offline Downloads catalog behind Play random, Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Cancel all downloads, Delete played downloads, Delete all downloads, Copy downloads, or Share downloads. In-progress downloads are not in this preview. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Home Continue listening preview, the Home New or Inbox preview, the Home Queue preview, the Home History preview, the Home Archived preview, the Home Favorites preview, the Library search remaining bar, the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var downloadsRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: downloadItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }

    /// VoiceOver context for Home welcome versus a search with no matching section previews.
    /// Visible ContentUnavailableView copy stays concise; this value adds soft-cap / Discover honesty.
    private var homeEmptyStateAccessibilityValue: String {
        if isSearchFiltering {
            return String(localized: "No episodes or podcasts in the visible Home section previews match your search. Clear or change the search. Discover is hidden while searching. Home shows soft-capped section previews — not the full Inbox, Queue, or Subscriptions tabs.")
        }
        if settings.isHomeSectionVisible(.discover) {
            return String(localized: "Home has no library previews to show yet. Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Or use Discover for Apple Charts. Customize sections under Settings → Home layout or Configure Home.")
        }
        return String(localized: "Home has no library previews to show yet. Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Customize sections under Settings → Home layout or Configure Home.")
    }

    /// Library content that would appear under visible non-Discover sections (respects search filter).
    private var hasVisibleLibraryContent: Bool {
        for id in settings.visibleHomeSections {
            switch id {
            case .continueListening:
                if !continueItems.isEmpty { return true }
            case .inbox:
                if !inboxItems.isEmpty { return true }
            case .queue:
                if !queueItems.isEmpty { return true }
            case .recentlyUpdated:
                if !recentFeeds.isEmpty { return true }
            case .favorites:
                if !favoriteItems.isEmpty { return true }
            case .downloads:
                if !downloadItems.isEmpty { return true }
            case .history:
                if !historyItems.isEmpty { return true }
            case .archived:
                if !archivedItems.isEmpty { return true }
            case .discover:
                continue
            }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(settings.visibleHomeSections) { sectionId in
                    homeSection(for: sectionId)
                }

                if isSearchFiltering && !hasVisibleLibraryContent {
                    ContentUnavailableView(
                        "No matching home items",
                        systemImage: "magnifyingglass",
                        description: Text("No episodes or podcasts on Home match your search.")
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No matching home items"))
                    .accessibilityValue(homeEmptyStateAccessibilityValue)
                    .accessibilityHint(String(localized: "Clear or change the Home search to see section previews again."))
                } else if !isSearchFiltering && !hasVisibleLibraryContent {
                    ContentUnavailableView(
                        "Welcome",
                        systemImage: "house",
                        description: Text(welcomeDescription)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Welcome"))
                    .accessibilityValue(homeEmptyStateAccessibilityValue)
                    .accessibilityHint(String(localized: "Use Configure Home or Settings → Home layout to show, hide, and reorder sections. Subscribe from Discover or Add podcast."))
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HomeLayoutSettingsView()
                    } label: {
                        Image(systemName: "rectangle.grid.1x2")
                    }
                    .accessibilityLabel(String(localized: "Configure Home"))
                    .accessibilityHint(
                        String(localized: "Opens Home layout to show, hide, and reorder Home sections. Same editor as Settings → Home layout. Optional History, Archived, Favorites, and Downloads previews are off by default.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Search home")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .navigationDestination(isPresented: $navigateToDiscover) {
                TopListsView()
            }
            .sheet(isPresented: $showDiscoverPINGate) {
                ParentalPINPromptSheet(
                    title: String(localized: "Parental controls"),
                    message: String(localized: "Enter your PIN to open Discover."),
                    onCancel: { showDiscoverPINGate = false },
                    onSuccess: { pin in
                        if parental.unlockSession(with: pin) {
                            showDiscoverPINGate = false
                            navigateToDiscover = true
                            return true
                        }
                        return false
                    }
                )
            }
            .refreshable {
                await store.refreshAllFeeds()
            }
            .overlay {
                if store.isLoading {
                    ProgressView(store.refreshProgressLabel)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(store.refreshProgressLabel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var welcomeDescription: String {
        if settings.isHomeSectionVisible(.discover) {
            return String(localized: "Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Or use Discover for Apple Charts. Customize sections under Settings → Home layout.")
        }
        return String(localized: "Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Customize sections under Settings → Home layout.")
    }

    @ViewBuilder
    private func homeSection(for id: HomeSectionId) -> some View {
        switch id {
        case .discover:
            // Charts preview is not title-filtered; hide while searching so empty state can show.
            if !isSearchFiltering {
                discoverSection
            }
        case .continueListening:
            if !continueItems.isEmpty {
                continueSection
            }
        case .inbox:
            if !inboxItems.isEmpty {
                inboxSection
            }
        case .queue:
            if !queueItems.isEmpty {
                queueSection
            }
        case .recentlyUpdated:
            if !recentFeeds.isEmpty {
                recentlyUpdatedSection
            }
        case .favorites:
            if !favoriteItems.isEmpty {
                favoritesSection
            }
        case .downloads:
            if !downloadItems.isEmpty {
                downloadsSection
            }
        case .history:
            if !historyItems.isEmpty {
                historySection
            }
        case .archived:
            if !archivedItems.isEmpty {
                archivedSection
            }
        }
    }

    @ViewBuilder
    private var discoverSection: some View {
        Section {
            HomeTopListsPreview()
        } header: {
            sectionHeader(String(localized: "Discover"), systemImage: "chart.bar")
        } footer: {
            Button {
                if parental.needsPINForAddDiscover {
                    showDiscoverPINGate = true
                } else {
                    navigateToDiscover = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("See all charts")
                        .font(.footnote)
                    if parental.needsPINForAddDiscover {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var continueSection: some View {
        Section {
            // AntennaPod-like Continue preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full continue catalog.
            if let remainingLabel = continueRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(continueRemainingAccessibilityLabel)
                    .accessibilityHint(continueRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(continueItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Last played"
                )
            }
        } header: {
            sectionHeader("Continue listening", systemImage: "play.circle")
        } footer: {
            NavigationLink {
                HistoryView()
            } label: {
                Text(store.continueListeningEpisodes.count > previewLimit ? "See all in History" : "Open History")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var inboxSection: some View {
        Section {
            // AntennaPod-like Inbox/New preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full Inbox / tab badge.
            if let remainingLabel = inboxRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(inboxRemainingAccessibilityLabel)
                    .accessibilityHint(inboxRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(inboxItems) { item in
                EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
            }
        } header: {
            homeSectionLink(
                title: String(localized: "New / Inbox"),
                systemImage: "tray.fill",
                tab: .inbox,
                total: store.inboxEpisodes.count
            )
        } footer: {
            if store.inboxEpisodes.count > previewLimit {
                Button("See all in Inbox") {
                    selectedTab = .inbox
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        Section {
            // AntennaPod-like Queue preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full Queue / tab badge / Queue chips.
            if let remainingLabel = queueRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(queueRemainingAccessibilityLabel)
                    .accessibilityHint(queueRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(queueItems) { episode in
                EpisodeRow(
                    episode: episode,
                    feedTitle: store.displayTitle(containingEpisodeId: episode.id)
                )
            }
        } header: {
            homeSectionLink(
                title: String(localized: "Queue"),
                systemImage: "list.bullet",
                tab: .queue,
                total: store.queue.count
            )
        } footer: {
            if store.queue.count > previewLimit {
                Button("See all in Queue") {
                    selectedTab = .queue
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var recentlyUpdatedSection: some View {
        Section {
            ForEach(recentFeeds) { feed in
                NavigationLink(value: feed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayTitle(for: feed))
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text("\(feed.episodes.count) episodes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let ms = feed.episodes.compactMap(\.pubDateEpochMs).max() {
                                let newestDate = Date(timeIntervalSince1970: Double(ms) / 1000)
                                Text(newestDate, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(
                                        String(localized: "Newest episode")
                                            + " "
                                            + EpisodeDateFormatting.listCaption(for: newestDate)
                                    )
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recentlyUpdatedFeedAccessibilityLabel(for: feed))
                .accessibilityValue(recentlyUpdatedFeedAccessibilityValue(for: feed))
                .accessibilityHint(String(localized: "Open podcast"))
            }
        } header: {
            sectionHeader("Recently updated", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            Button("See all subscriptions") {
                selectedTab = .subscriptions
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            // AntennaPod-like History preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full History / Clear count.
            if let remainingLabel = historyRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(historyRemainingAccessibilityLabel)
                    .accessibilityHint(historyRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(historyItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Last played"
                )
            }
        } header: {
            sectionHeader("History", systemImage: "clock.arrow.circlepath")
        } footer: {
            NavigationLink {
                HistoryView()
            } label: {
                Text(store.historyEpisodes.count > previewLimit ? "See all in History" : "Open History")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        Section {
            // AntennaPod-like Archived preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full Archived / Restore count.
            if let remainingLabel = archivedRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(archivedRemainingAccessibilityLabel)
                    .accessibilityHint(archivedRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(archivedItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.archivedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Archived"
                )
            }
        } header: {
            sectionHeader("Archived", systemImage: "archivebox")
        } footer: {
            NavigationLink {
                ArchivedView()
            } label: {
                Text(store.archivedEpisodes.count > previewLimit ? "See all in Archived" : "Open Archived")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        Section {
            // AntennaPod-like Favorites preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full Favorites / Clear count.
            if let remainingLabel = favoritesRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(favoritesRemainingAccessibilityLabel)
                    .accessibilityHint(favoritesRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(favoriteItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.favoritedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Favorited"
                )
            }
        } header: {
            sectionHeader("Favorites", systemImage: "star")
        } footer: {
            NavigationLink {
                FavoritesView()
            } label: {
                Text(store.favoriteEpisodes.count > previewLimit ? "See all Favorites" : "Open Favorites")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var downloadsSection: some View {
        Section {
            // AntennaPod-like Downloads preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full Downloads / tab badge.
            if let remainingLabel = downloadsRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(downloadsRemainingAccessibilityLabel)
                    .accessibilityHint(downloadsRemainingAccessibilityHint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(downloadItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: store.displayTitle(containingEpisodeId: item.episode.id),
                    dateOverride: item.downloadedAtEpochMs.map {
                        Date(timeIntervalSince1970: Double($0) / 1000)
                    },
                    dateAccessibilityLabel: "Downloaded"
                )
            }
        } header: {
            homeSectionLink(
                title: String(localized: "Downloads"),
                systemImage: "arrow.down.circle",
                tab: .downloads,
                total: downloads.downloads.count
            )
        } footer: {
            Button {
                selectedTab = .downloads
            } label: {
                Text(downloads.downloads.count > previewLimit ? "See all in Downloads" : "Open Downloads")
                    .font(.footnote)
            }
        }
    }

    private func recentlyUpdatedFeedAccessibilityLabel(for feed: PodcastFeed) -> String {
        let title = store.displayTitle(for: feed).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Podcast title unavailable") : String(localized: "Podcast \(title)")
    }

    private func recentlyUpdatedFeedAccessibilityValue(for feed: PodcastFeed) -> String {
        let episodeCount = feed.episodes.count
        var parts = [
            episodeCount == 1
                ? String(localized: "1 episode")
                : String(localized: "\(episodeCount) episodes")
        ]
        if let ms = feed.episodes.compactMap(\.pubDateEpochMs).max() {
            let newestDate = Date(timeIntervalSince1970: Double(ms) / 1000)
            parts.append(
                String(localized: "Newest episode")
                    + " "
                    + EpisodeDateFormatting.listCaption(for: newestDate)
            )
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    @ViewBuilder
    private func homeSectionLink(title: String, systemImage: String, tab: RootTab, total: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if total > 0 {
                Text("\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                selectedTab = tab
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Open \(title)"))
        }
    }

    /// Episode-like items (Continue / Inbox / Favorites / History / Archived): library query fields
    /// via `episodeMatchesLibraryQuery` and/or `feedTitle` (display title on those wrappers).
    private func filterEpisodes<T>(_ items: [T]) -> [T] where T: HomeSearchableEpisode {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            store.episodeMatchesLibraryQuery(item.episode, query: q)
                || item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private func scheduleFilter(for term: String) {
        debounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            debouncedQuery = trimmed
        }
    }
}

/// Shared episode + feedTitle fields for Home section episode previews (Continue / Inbox / History / Favorites / Archived).
private protocol HomeSearchableEpisode {
    var episode: PodcastEpisode { get }
    var feedTitle: String { get }
}

extension HistoryEpisode: HomeSearchableEpisode {}
extension InboxEpisode: HomeSearchableEpisode {}
extension FavoriteEpisode: HomeSearchableEpisode {}
extension ArchivedEpisode: HomeSearchableEpisode {}

