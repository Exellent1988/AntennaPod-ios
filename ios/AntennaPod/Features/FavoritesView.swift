import SwiftUI
import UIKit

struct FavoritesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearFavoritesConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showEnqueueAllUnplayedConfirm = false
    @State private var showMarkAllPlayedConfirm = false
    @State private var showMarkAllUnplayedConfirm = false
    @State private var showArchiveAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full favorites catalog (store order: newest favorited first) — Clear favorites always uses this count.
    private var items: [FavoriteEpisode] {
        store.favoriteEpisodes
    }

    /// Episodes from the **full Favorites catalog** (`store.favoriteEpisodes`, newest-favorited first) that are
    /// not already queued — same catalog as Clear favorites, **not** the podcast-chip or searchable filtered list.
    /// Confirm count and `enqueueAllFavorites()` share this eligibility.
    private var enqueueAllFavoritesCandidatesCount: Int {
        items.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Unplayed, non-archived, not-already-queued episodes in the full Favorites catalog.
    /// Confirm count and enqueue action share this catalog-scoped eligibility; UI filters are ignored.
    private var enqueueAllUnplayedFavoritesCandidatesCount: Int {
        store.enqueueAllUnplayedFavoritesCandidates().count
    }

    private var markAllFavoritesPlayedCandidatesCount: Int {
        store.markAllFavoritesPlayedCandidateCount()
    }

    private var markAllFavoritesUnplayedCandidatesCount: Int {
        store.markAllFavoritesUnplayedCandidateCount()
    }

    /// Non-archived episodes in the full Favorites catalog — not podcast, search, or sort filtered.
    private var archiveAllFavoritesCandidatesCount: Int {
        items.filter { !store.isArchived($0.episode.id) }.count
    }

    /// Favorited episodes with playable media via shared `EpisodePlayRandom` (local file via
    /// `DownloadService.localURL` — downloads + local-folder `file://` — or streamable http(s)
    /// `downloadUrl`). Full Favorites catalog — **not** podcast-chip or searchable filtered.
    /// Distinct from Clear favorites / Add all to queue / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: items.map(\.episode),
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible favorite is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: FavoritesPodcastFilter {
        FavoritesPodcastFilter.fromStorage(settings.favoritesPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one favorite episode.
    /// Built from the Favorites catalog via `feed(containingEpisodeId:)` — never invent.
    /// Order matches the chip label: display title (custom title when set, else RSS title).
    private var favoritesPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in items {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return favoritesPodcastsByDisplayTitle(feeds)
    }

    /// A–Z by the name the chip shows. Raw RSS title would place a renamed podcast
    /// where the old name sorts, so the visible label and the row disagree.
    private func favoritesPodcastsByDisplayTitle(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        feeds.sorted {
            store.displayTitle(for: $0).localizedCaseInsensitiveCompare(
                store.displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    private var podcastFilterChips: [FavoritesPodcastFilter] {
        var chips: [FavoritesPodcastFilter] = [.all]
        var feeds = favoritesPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has favorites)
        // so the user can see why the list is empty and tap All.
        if case .feed(let id) = podcastFilter,
           !feeds.contains(where: { $0.id == id }),
           let feed = store.feeds.first(where: { $0.id == id }) {
            feeds.append(feed)
            feeds = favoritesPodcastsByDisplayTitle(feeds)
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later Favorites row looks filtered out.
    /// A still-subscribed feed with zero Favorites episodes keeps its chip.
    private func releaseFavoritesPodcastFilterIfFeedGone() {
        guard case .feed(let id) = FavoritesPodcastFilter.fromStorage(settings.favoritesPodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.favoritesPodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: FavoritesPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.nonEmptyDisplayTitle(forFeedId: id)
                ?? favoritesPodcastFeeds.first(where: { $0.id == id }).flatMap { store.nonEmptyDisplayTitle(for: $0) }
                ?? String(localized: "Unknown podcast")
        }
    }

    private var isSearching: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Visible favorites: podcast chip → search → `favoritesSort`.
    /// Date modes: `FavoriteEpisode.favoritedAtEpochMs` (`favoriteAtById` / `favorites.json`).
    /// Duration modes: known duration via `EpisodeRemainingTime.knownDurationSeconds`
    /// (feed when known, else saved playback — same path as Queue / Inbox / History / Archived;
    /// never invent; unknown last). Stable tiebreaker episode `id`.
    /// Empty query shows the podcast-filtered list; sort applies to search-filtered results too.
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail / Queue), plus
    /// feed title (`FavoriteEpisode.feedTitle` = display title). View-only —
    /// Does not mutate `PodcastStore.favoriteEpisodes` (Home Favorites preview / Clear favorites stay newest-first catalog).
    /// Clear favorites / Add all to queue / Play random / Copy / Share stay full-catalog scoped.
    private var filteredItems: [FavoriteEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterPodcast: [FavoriteEpisode]
        switch podcastFilter {
        case .all:
            afterPodcast = items
        case .feed(let feedId):
            afterPodcast = items.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        let filtered: [FavoriteEpisode]
        if q.isEmpty {
            filtered = afterPodcast
        } else {
            filtered = afterPodcast.filter { item in
                if store.episodeMatchesLibraryQuery(item.episode, query: q) { return true }
                return item.feedTitle.localizedSearchContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.favoritesSort {
            case .newestFirst:
                if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                    return lhs.favoritedAtEpochMs > rhs.favoritedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                    return lhs.favoritedAtEpochMs < rhs.favoritedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .shortestFirst, .longestFirst:
                let shortestFirst = settings.favoritesSort == .shortestFirst
                switch (
                    knownDurationSecondsForFavoritesSort(lhs.episode),
                    knownDurationSecondsForFavoritesSort(rhs.episode)
                ) {
                case let (l?, r?):
                    if l != r {
                        return shortestFirst ? (l < r) : (l > r)
                    }
                    return lhs.episode.id < rhs.episode.id
                case (_?, nil):
                    return true // known before unknown
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.episode.id < rhs.episode.id
                }
            case .titleAscending, .titleDescending:
                return favoritesTitleSort(lhs.episode, rhs.episode, ascending: settings.favoritesSort == .titleAscending)
            }
        }
    }

    /// Feed duration when known; else saved playback duration. Never invents a length.
    private func knownDurationSecondsForFavoritesSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Title A–Z / Z–A: empty titles last; id tiebreak.
    private func favoritesTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Favorites list
    /// (podcast chip + searchable filter + sort). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0; **unknown duration skipped** (tilde when any skipped). Currently playing uses live
    /// `PlaybackService` position/duration. Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// Distinct from Clear favorites / Add all to queue / Play random eligibility (always full catalog).
    private var favoritesRemainingInfoLabel: String? {
        guard !filteredItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: favoritesRemainingSummary)
    }

    private var favoritesRemainingAccessibilityLabel: String {
        guard let label = favoritesRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Favorites remaining time \(label)")]
        let unknown = favoritesRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Favorites remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and that the bar is the podcast+search+sort list.
    private var favoritesRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Favorites bar is the visible list after the podcast filter, search, and sort. Sort changes order only. Played episodes that are not currently playing count as zero. It is not the full Favorites catalog behind Clear favorites, Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Play random, Copy favorites, or Share favorites, and not the Home Favorites preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the All Episodes remaining bar, the Queue remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Favorites bar is the visible list after the podcast filter, search, and sort. Sort changes order only. Played episodes that are not currently playing count as zero. It is not the full Favorites catalog behind Clear favorites, Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Play random, Copy favorites, or Share favorites, and not the Home Favorites preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the All Episodes remaining bar, the Queue remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    /// VoiceOver context for the two different empty states. Keep the catalog-empty
    /// message distinct from a podcast/search mismatch so the user knows whether to
    /// add a favorite or change the current filter.
    private var favoritesEmptyStateAccessibilityValue: String {
        if items.isEmpty {
            return String(localized: "There are no favorited episodes. Star an episode from a feed or the full player to add it to Favorites.")
        }
        if isPodcastFiltering && !isSearching {
            return String(localized: "The selected podcast has no favorited episodes. Episodes remain in the full Favorites catalog. Clear favorites, Add all to queue, Mark all, Archive all, Play random, Copy, and Share still use the full Favorites, not this empty view.")
        }
        return String(localized: "No favorited episodes match your search. Episodes remain in the full Favorites catalog. Clear favorites, Add all to queue, Mark all, Archive all, Play random, Copy, and Share still use the full Favorites, not this empty view.")
    }

    /// VoiceOver recovery hint for the podcast/search mismatch empty state only.
    private var favoritesNoMatchAccessibilityHint: String {
        if isPodcastFiltering && !isSearching {
            return String(localized: "Choose All or another podcast filter to see other Favorites. This does not unstar episodes or clear Favorites.")
        }
        return String(localized: "Change or clear search to see other Favorites. This does not unstar episodes or clear Favorites.")
    }

    private var favoritesRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredItems.map(\.episode),
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


    /// Plain-text list of the **full** Favorites catalog — not podcast-chip / search / UI sort filtered.
    /// Same honesty as Clear favorites / Add all to queue / Play random (`store.favoriteEpisodes`, newest favorited first).
    private var favoritesPlainText: String {
        FavoritesExport.plainText(episodes: items.map(\.episode)) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the full Favorites catalog is non-empty (read-only export).
    private var canExportFavorites: Bool {
        !items.isEmpty
    }

    /// “Favorites” header + body for system share sheet (same body as Copy).
    private var favoritesShareText: String {
        FavoritesExport.shareText(episodes: items.map(\.episode)) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }


    var body: some View {
        List {
            if !items.isEmpty, !favoritesPodcastFeeds.isEmpty || isPodcastFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(podcastFilterChips) { chip in
                                FavoritesPodcastFilterChip(
                                    title: podcastChipTitle(chip),
                                    selected: podcastFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Favorites list by podcast")
                                ) {
                                    settings.favoritesPodcastFilter = chip.storageValue
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: {
                    Text("Podcasts")
                }
            }

            // AntennaPod-like favorites info bar (visible sorted+podcast+search filtered list remaining time).
            // Hidden when catalog empty or filters match nothing — not full-catalog Clear count.
            if let remainingLabel = favoritesRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(favoritesRemainingAccessibilityLabel)
                        .accessibilityHint(favoritesRemainingAccessibilityHint)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Star episodes from a feed or the full player. Favorites keep their downloads when auto-delete after playing is on.")
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No favorites yet"))
                .accessibilityValue(favoritesEmptyStateAccessibilityValue)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching favorites",
                    systemImage: "magnifyingglass",
                    description: Text(
                        isPodcastFiltering && !isSearching
                            ? String(localized: "No favorites match your filter.")
                            : String(localized: "No favorites match your search.")
                    )
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No matching favorites"))
                .accessibilityValue(favoritesEmptyStateAccessibilityValue)
                .accessibilityHint(favoritesNoMatchAccessibilityHint)
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.favoritedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Favorited")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.toggleFavorite(item.episode.id)
                        } label: {
                            Label("Unfavorite", systemImage: "star.slash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            store.togglePlayed(item.episode.id)
                        } label: {
                            Label(
                                store.isPlayed(item.episode.id)
                                    ? String(localized: "Mark unplayed")
                                    : String(localized: "Mark played"),
                                systemImage: store.isPlayed(item.episode.id) ? "circle" : "checkmark.circle"
                            )
                        }
                        .tint(.blue)
                        .accessibilityHint(
                            store.isPlayed(item.episode.id)
                                ? String(localized: "Marks this episode as unplayed")
                                : String(localized: "Marks this episode as played")
                        )
                        Button {
                            // Archived episodes stay in Favorites, so this swipe must undo
                            // as well as archive — same toggle as the row button. A one-way
                            // archive() leaves the action labeled Archive and does nothing.
                            store.toggleArchived(item.episode.id)
                        } label: {
                            Label(
                                store.isArchived(item.episode.id)
                                    ? String(localized: "Restore")
                                    : String(localized: "Archive"),
                                systemImage: store.isArchived(item.episode.id)
                                    ? "arrow.uturn.backward"
                                    : "archivebox"
                            )
                        }
                        .tint(store.isArchived(item.episode.id) ? .green : .orange)
                        .accessibilityHint(
                            store.isArchived(item.episode.id)
                                ? String(localized: "Restores this episode from the archive")
                                : String(localized: "Hides this episode from Inbox without marking it played")
                        )
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search favorites")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onAppear {
            releaseFavoritesPodcastFilterIfFeedGone()
        }
        .onChange(of: store.feeds.map(\.id)) { _, _ in
            releaseFavoritesPodcastFilterIfFeedGone()
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.favoritesSort) {
                        ForEach(FavoritesSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort favorites"))
                .accessibilityHint(String(localized: "Orders the Favorites list. Shortest and Longest use known duration; Title A–Z / Z–A by title; empty or unknown last. Home Favorites preview stays newest-first."))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyFavorites()
                    } label: {
                        Label("Copy favorites", systemImage: "doc.plaintext")
                    }
                    // Full Favorites catalog (not podcast/search/UI sort).
                    .disabled(!canExportFavorites)
                    .accessibilityLabel(String(localized: "Copy favorites"))
                    .accessibilityHint(
                        String(localized: "Copies the full favorites list to the pasteboard")
                    )

                    ShareLink(
                        item: favoritesShareText,
                        subject: Text(String(localized: "Favorites"))
                    ) {
                        Label("Share favorites", systemImage: "square.and.arrow.up")
                    }
                    // Same gates as Copy favorites — full catalog.
                    .disabled(!canExportFavorites)
                    .accessibilityLabel(String(localized: "Share favorites"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the full favorites list")
                    )

                    Button {
                        playRandomEpisode()
                    } label: {
                        Label("Play random", systemImage: "shuffle")
                    }
                    .disabled(playRandomCandidates.isEmpty)
                    .accessibilityLabel(String(localized: "Play random"))
                    .accessibilityHint(String(localized: "Plays a random episode from the full Favorites catalog with playable media. Prefers unplayed when any remain. Ignores podcast, search, and sort filters. Does not reorder Favorites. No confirmation."))

                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllFavoritesCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Asks for confirmation, then appends episodes from the full Favorites catalog that are not already queued, newest favorited first. Ignores podcast, search, and sort filters. Queue lock does not block enqueue."))

                    Button {
                        showEnqueueAllUnplayedConfirm = true
                    } label: {
                        Label("Add all unplayed to queue", systemImage: "text.badge.plus")
                    }
                    .disabled(enqueueAllUnplayedFavoritesCandidatesCount == 0)
                    .accessibilityLabel(String(localized: "Add all unplayed to queue"))
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then appends unplayed, non-archived episodes from the full Favorites catalog that are not already queued, newest favorited first. Ignores podcast, search, and sort filters. Queue lock does not block enqueue. Distinct from Add all to queue, which also includes played and archived.")
                    )

                    Button {
                        showMarkAllPlayedConfirm = true
                    } label: {
                        Label("Mark all as played", systemImage: "checkmark.circle")
                    }
                    .disabled(markAllFavoritesPlayedCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then marks unplayed, non-archived episodes in the full Favorites catalog as played, newest favorited first. Ignores podcast, search, and sort filters. Auto-delete after playing still applies when enabled; does not clear Favorites, unfavorite episodes, or delete downloads itself.")
                    )

                    Button {
                        showMarkAllUnplayedConfirm = true
                    } label: {
                        Label("Mark all as unplayed", systemImage: "circle")
                    }
                    .disabled(markAllFavoritesUnplayedCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then marks played episodes, including archived, in the full Favorites catalog as unplayed. Ignores podcast, search, and sort filters. Does not delete download files, clear the queue, stop playback, or unarchive episodes.")
                    )

                    Button {
                        showArchiveAllConfirm = true
                    } label: {
                        Label("Archive all", systemImage: "archivebox")
                    }
                    .disabled(archiveAllFavoritesCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then archives non-archived episodes in the full Favorites catalog, newest favorited first. Ignores podcast, search, and sort filters. Archived does not mean played. Does not mark played, delete downloads, or clear the queue.")
                    )

                    Button(role: .destructive) {
                        showClearFavoritesConfirm = true
                    } label: {
                        Label("Clear favorites", systemImage: "trash")
                    }
                    // Clear always targets the full favorites list (not the filtered subset).
                    .disabled(items.isEmpty)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then removes every episode from the full Favorites catalog. Ignores podcast, search, and sort filters. Does not delete downloads, archive, mark played, or clear the queue.")
                    )
                } label: {
                    Label("Favorites actions", systemImage: "ellipsis.circle")
                }
                // Menu stays available when catalog non-empty so Play random / Add all can disable per eligibility.
                .disabled(items.isEmpty)
                .accessibilityLabel(String(localized: "Favorites actions"))
                .accessibilityHint(
                    String(localized: "Copy favorites, share favorites, play random, add all to queue, add all unplayed to queue, mark all as played, mark all as unplayed, archive all, or clear favorites")
                )
            }
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCopiedAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedAlertMessage)
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTick)
        .confirmationDialog(
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllFavoritesCandidatesCount) favorite episodes to the end of the queue (newest favorited first). Already queued episodes are skipped. Uses the full Favorites catalog (same as Clear favorites), not the podcast or searchable filter. Queue lock does not block enqueue.")
        }
        .confirmationDialog(
            "Add all unplayed to queue?",
            isPresented: $showEnqueueAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all unplayed to queue") {
                store.enqueueAllUnplayedFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllUnplayedFavoritesCandidatesCount) unplayed, non-archived favorite episodes to the end of the queue (newest favorited first). Already queued, played, and archived episodes are skipped. Uses the full Favorites catalog (same as Clear favorites), not the podcast, search, or sort filter. Queue lock does not block enqueue. Distinct from Add all to queue, which also includes played and archived episodes.")
        }
        .confirmationDialog(
            "Mark all as played?",
            isPresented: $showMarkAllPlayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as played") {
                store.markAllFavoritesPlayed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks \(markAllFavoritesPlayedCandidatesCount) unplayed, non-archived favorite episode(s) as played. Uses the full Favorites catalog (newest favorited first), not the podcast, search, or sort filter. Auto-delete after playing still applies when enabled; this does not clear Favorites, unfavorite episodes, or delete downloads itself.")
        }
        .confirmationDialog(
            "Mark all as unplayed?",
            isPresented: $showMarkAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as unplayed") {
                store.markAllFavoritesUnplayed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks \(markAllFavoritesUnplayedCandidatesCount) played favorite episode(s), including archived episodes, as unplayed. Uses the full Favorites catalog (newest favorited first), not the podcast, search, or sort filter. Does not delete download files, clear the queue, stop playback, or unarchive episodes.")
        }
        .confirmationDialog(
            "Archive all?",
            isPresented: $showArchiveAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive all") {
                store.archiveAllFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archives \(archiveAllFavoritesCandidatesCount) non-archived favorite episode(s) in the full Favorites catalog (newest favorited first), not the podcast, search, or sort filter. Archived does not mean played. Does not mark played, delete downloads, or clear the queue.")
        }
        .confirmationDialog(
            "Clear favorites?",
            isPresented: $showClearFavoritesConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear favorites", role: .destructive) {
                store.clearFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(items.count) episodes from favorites. Does not delete downloads, archive, mark played, or clear the queue.")
        }
    }

    /// Pasteboard copy of the **full** Favorites catalog (not podcast/search/UI sort). Read-only.
    private func copyFavorites() {
        let text = favoritesPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Favorites copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does not invent queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = EpisodePlayRandom.pick(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        ) else { return }
        _ = playback.play(episode: episode)
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

/// Filter chip for Favorites podcast chips (mirrors Inbox / Queue / Downloads).
private struct FavoritesPodcastFilterChip: View {
    let title: String
    let selected: Bool
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
