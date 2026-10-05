import SwiftUI
import UIKit

struct InboxView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showMarkAllPlayedConfirm = false
    @State private var showMarkAllUnplayedConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showEnqueueAllUnplayedConfirm = false
    @State private var showArchiveAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full Inbox catalog ordered by `AppSettings.inboxSort`.
    /// Date modes: `pubDateEpochMs` (missing last). Duration modes: known duration via
    /// `EpisodeRemainingTime.knownDurationSeconds` (feed when known, else saved playback —
    /// same path as Queue / Feed / All Episodes; never invent; unknown last).
    /// Title modes: `localizedCaseInsensitiveCompare` (empty titles last).
    /// Stable tiebreaker is episode `id` (no `dateAdded` on `PodcastEpisode`).
    /// Does not mutate `PodcastStore.inboxEpisodes` (Home New preview stays newest-first).
    /// Used for current-Inbox bulk Mark all as played / Archive all counts.
    private var sortedItems: [InboxEpisode] {
        store.inboxEpisodes.sorted { lhs, rhs in
            switch settings.inboxSort {
            case .newestFirst:
                let l = lhs.episode.pubDateEpochMs ?? Int64.min
                let r = rhs.episode.pubDateEpochMs ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                let l = lhs.episode.pubDateEpochMs ?? Int64.max
                let r = rhs.episode.pubDateEpochMs ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            case .shortestFirst, .longestFirst:
                let shortestFirst = settings.inboxSort == .shortestFirst
                switch (
                    knownDurationSecondsForInboxSort(lhs.episode),
                    knownDurationSecondsForInboxSort(rhs.episode)
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
                return inboxTitleSort(lhs.episode, rhs.episode, ascending: settings.inboxSort == .titleAscending)
            }
        }
    }

    /// Feed duration when known; else saved playback duration. Never invents a length.
    private func knownDurationSecondsForInboxSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Title A–Z / Z–A: empty titles last; id tiebreak.
    private func inboxTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: InboxPodcastFilter {
        InboxPodcastFilter.fromStorage(settings.inboxPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one Inbox episode.
    /// Built from the Inbox catalog via `feed(containingEpisodeId:)` — never invent.
    /// Order matches the chip label: display title (custom title when set, else RSS title).
    private var inboxPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in store.inboxEpisodes {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return inboxPodcastsByDisplayTitle(feeds)
    }

    /// A–Z by the name the chip shows. Raw RSS title would place a renamed podcast
    /// where the old name sorts, so the visible label and the row disagree.
    private func inboxPodcastsByDisplayTitle(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        feeds.sorted {
            store.displayTitle(for: $0).localizedCaseInsensitiveCompare(
                store.displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    private var podcastFilterChips: [InboxPodcastFilter] {
        var chips: [InboxPodcastFilter] = [.all]
        var feeds = inboxPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has Inbox items)
        // so the user can see why the list is empty and tap All.
        if case .feed(let id) = podcastFilter,
           !feeds.contains(where: { $0.id == id }),
           let feed = store.feeds.first(where: { $0.id == id }) {
            feeds.append(feed)
            feeds = inboxPodcastsByDisplayTitle(feeds)
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later Inbox row looks filtered out.
    /// A still-subscribed feed with zero Inbox episodes keeps its chip.
    private func releaseInboxPodcastFilterIfFeedGone() {
        guard case .feed(let id) = InboxPodcastFilter.fromStorage(settings.inboxPodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.inboxPodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: InboxPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.nonEmptyDisplayTitle(forFeedId: id)
                ?? inboxPodcastFeeds.first(where: { $0.id == id }).flatMap { store.nonEmptyDisplayTitle(for: $0) }
                ?? String(localized: "Unknown podcast")
        }
    }

    /// Visible Inbox rows: `inboxSort` → podcast chip → itunes:episodeType chip.
    /// Library `.searchable` replaces this list entirely (`LibrarySearchResultsView`).
    /// View-only — Mark all / Mark all as unplayed / Add all to queue / Archive all / Play random / Copy inbox / Share inbox stay full-catalog scoped.
    private var filteredItems: [InboxEpisode] {
        var base: [InboxEpisode]
        switch podcastFilter {
        case .all:
            base = sortedItems
        case .feed(let feedId):
            base = sortedItems.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        if settings.inboxEpisodeTypeFilter != .all {
            base = base.filter { settings.inboxEpisodeTypeFilter.matches($0.episode) }
        }
        return base
    }

    /// Type chips for the full Inbox catalog (before podcast/type). Hide zero-match.
    private var episodeTypeFilterChips: [EpisodeTypeFilter] {
        EpisodeTypeFilter.chips(
            presentIn: store.inboxEpisodes.map(\.episode),
            selected: settings.inboxEpisodeTypeFilter
        )
    }

    private var showEpisodeTypeFilterChips: Bool {
        EpisodeTypeFilter.shouldShowChipRow(
            presentIn: store.inboxEpisodes.map(\.episode),
            selected: settings.inboxEpisodeTypeFilter
        )
    }

    private var isEpisodeTypeFiltering: Bool {
        settings.inboxEpisodeTypeFilter != .all
    }

    private var isSearching: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Episodes from the **full Inbox catalog** (`store.inboxEpisodes`, newest-first) that are
    /// not already queued — same catalog as Mark all / Archive all, **not** library-search hits
    /// and **not** the podcast-chip filtered subset.
    /// Confirm count and `enqueueAllInbox()` share this eligibility. Menu disabled while searching.
    private var enqueueAllInboxCandidatesCount: Int {
        store.inboxEpisodes.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Unplayed, non-archived, not-already-queued episodes in the full Inbox catalog.
    /// Inbox is normally unplayed-only, so this may match Add all to queue in practice; the
    /// explicit guards preserve the feature's eligibility contract.
    private var enqueueAllUnplayedInboxCandidatesCount: Int {
        store.enqueueAllUnplayedInboxCandidates().count
    }

    /// Full Inbox catalog episodes that are still non-archived. The Inbox normally excludes
    /// archived episodes, but keep eligibility explicit so the bulk action cannot archive
    /// anything outside its catalog scope.
    private var archiveAllInboxCandidatesCount: Int {
        store.inboxEpisodes.filter { !store.isArchived($0.episode.id) }.count
    }

    /// Played episodes in the full stored feed catalog behind Inbox, including archived episodes.
    /// Inbox itself is unplayed-only, so this reverse action must not use `sortedItems`.
    private var markAllInboxUnplayedCandidatesCount: Int {
        store.markAllInboxUnplayedCandidateCount()
    }

    /// Inbox episodes with playable media via shared `EpisodePlayRandom` (local file via
    /// `DownloadService.localURL` — downloads + local-folder `file://` — or streamable http(s)
    /// `downloadUrl`). Full Inbox catalog — **not** podcast-chip, episode-type, or library-search filtered.
    /// Distinct from Mark all / Mark all as unplayed / Add all to queue / Archive all / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: store.inboxEpisodes.map(\.episode),
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible.
    /// Inbox is already unplayed-only (`!isPlayed` && not archived), so prefer-unplayed is a no-op
    /// in practice — same shared `EpisodePlayRandom` as History / Favorites / Feed / Queue / Downloads.
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Visible Inbox rows for remaining-time: podcast+type-filtered sorted list when **not** in
    /// library-search mode. While `.searchable` shows `LibrarySearchResultsView` (full library),
    /// the info bar is hidden — do not report full-Inbox / tab-badge totals over a different surface.
    private var visibleInboxForRemaining: [InboxEpisode] {
        isSearching ? [] : filteredItems
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered Inbox list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from tab badge / Mark all / Mark all as unplayed / Add all / Archive all / Play random / Copy inbox / Share inbox (full catalog).
    private var inboxRemainingInfoLabel: String? {
        guard !visibleInboxForRemaining.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: inboxRemainingSummary)
    }

    private var inboxRemainingAccessibilityLabel: String {
        guard let label = inboxRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Inbox remaining time \(label)")]
        let unknown = inboxRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Inbox remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and what the bar is not.
    private var inboxRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. Inbox is unplayed and not archived, including in-progress episodes, over the visible list after sort, podcast filter, and episode type. Sort changes order only. It is not the All Episodes newest-500 cap, not the full catalog behind the tab badge, Mark all, Add all to queue, Archive all, Play random, Copy, or Share, and not library-search episode hits. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Subscriptions unplayed remaining bar, the Home New / Inbox preview, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. Inbox is unplayed and not archived, including in-progress episodes, over the visible list after sort, podcast filter, and episode type. Sort changes order only. It is not the All Episodes newest-500 cap, not the full catalog behind the tab badge, Mark all, Add all to queue, Archive all, Play random, Copy, or Share, and not library-search episode hits. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Subscriptions unplayed remaining bar, the Home New / Inbox preview, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var inboxRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: visibleInboxForRemaining.map(\.episode),
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

    /// VoiceOver context for an empty Inbox catalog versus a podcast/type/search mismatch.
    /// The visible ContentUnavailableView copy stays concise; this value explains the next
    /// useful action without changing Inbox filtering or catalog semantics.
    private var inboxEmptyStateAccessibilityValue: String {
        if store.inboxEpisodes.isEmpty {
            return String(localized: "There are no new or unplayed episodes in Inbox. New and unplayed episodes from your subscriptions appear here. Use Search library to find any episode or podcast in your library.")
        }
        if isSearching {
            return String(localized: "No Inbox episodes match your search. Clear or change the search to see Inbox.")
        }
        if isPodcastFiltering && isEpisodeTypeFiltering {
            return String(localized: "No Inbox episodes match the selected podcast and episode type filters. Choose All for the podcast or episode type to see more episodes.")
        }
        if isPodcastFiltering {
            return String(localized: "The selected podcast has no matching Inbox episodes. Choose All or another podcast filter.")
        }
        if isEpisodeTypeFiltering {
            return String(localized: "No Inbox episodes match the selected episode type. Choose All or another episode type.")
        }
        return String(localized: "No Inbox episodes match the active filters. Choose All or another filter.")
    }


    /// Full Inbox catalog episodes in **store** newest-first order (`PodcastStore.inboxEpisodes`).
    /// **Not** podcast-chip / episode-type / UI `inboxSort` / library-search filtered.
    /// Same honesty as Mark all / Mark all as unplayed / Archive all / Add all / Play random / tab badge.
    private var inboxCatalogEpisodes: [PodcastEpisode] {
        store.inboxEpisodes.map(\.episode)
    }

    /// Plain-text list of the **full** Inbox catalog — not chip/type/sort/search filtered.
    private var inboxPlainText: String {
        InboxExport.plainText(episodes: inboxCatalogEpisodes) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the full Inbox catalog is non-empty (read-only export).
    private var canExportInbox: Bool {
        !store.inboxEpisodes.isEmpty
    }

    /// “Inbox” header + body for system share sheet (same body as Copy).
    private var inboxShareText: String {
        InboxExport.shareText(episodes: inboxCatalogEpisodes) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Podcast chips — hidden while library search replaces Inbox rows.
                if !isSearching,
                   !store.inboxEpisodes.isEmpty,
                   !inboxPodcastFeeds.isEmpty || isPodcastFiltering {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(podcastFilterChips) { chip in
                                    InboxPodcastFilterChip(
                                        title: podcastChipTitle(chip),
                                        selected: podcastFilter == chip,
                                        accessibilityHint: String(localized: "Filters the Inbox list by podcast")
                                    ) {
                                        settings.inboxPodcastFilter = chip.storageValue
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

                // itunes:episodeType chips — hide when no types in Inbox catalog / while searching.
                if !isSearching, !store.inboxEpisodes.isEmpty, showEpisodeTypeFilterChips {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(episodeTypeFilterChips) { chip in
                                    InboxPodcastFilterChip(
                                        title: chip.label,
                                        selected: settings.inboxEpisodeTypeFilter == chip,
                                        accessibilityHint: String(localized: "Filters the Inbox list by episode type")
                                    ) {
                                        settings.inboxEpisodeTypeFilter = chip
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }

                // AntennaPod-like inbox info bar (visible sorted+podcast+type-filtered Inbox remaining time).
                // Hidden while library search replaces the Inbox rows.
                if let remainingLabel = inboxRemainingInfoLabel {
                    Section {
                        Text(remainingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(inboxRemainingAccessibilityLabel)
                            .accessibilityHint(inboxRemainingAccessibilityHint)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }

                if isSearching {
                    LibrarySearchResultsView(query: debouncedQuery)
                } else if store.inboxEpisodes.isEmpty {
                    ContentUnavailableView(
                        "Inbox empty",
                        systemImage: "tray",
                        description: Text("New and unplayed episodes from your subscriptions appear here. Use search to find any episode or podcast in your library.")
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Inbox empty"))
                    .accessibilityValue(inboxEmptyStateAccessibilityValue)
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No matching inbox episodes",
                        systemImage: "magnifyingglass",
                        description: Text(
                            (isPodcastFiltering || isEpisodeTypeFiltering)
                                ? String(localized: "No inbox episodes match your filter.")
                                : String(localized: "No inbox episodes match your search.")
                        )
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "No matching inbox episodes"))
                    .accessibilityValue(inboxEmptyStateAccessibilityValue)
                } else {
                    ForEach(filteredItems) { item in
                        EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    store.playNext(
                                        item.episode,
                                        currentlyPlayingId: playback.currentEpisode?.id
                                    )
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                .tint(.teal)
                                Button {
                                    store.enqueue(item.episode)
                                } label: {
                                    Label("Add to queue", systemImage: "text.append")
                                }
                                .tint(.purple)
                                Button {
                                    store.archive(item.episode.id)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.markPlayed(item.episode.id)
                                } label: {
                                    Label("Mark played", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                                .accessibilityHint(String(localized: "Marks this episode as played"))
                            }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $settings.inboxSort) {
                            ForEach(InboxSort.allCases) { sort in
                                Label(sort.label, systemImage: sort.systemImage)
                                    .tag(sort)
                            }
                        } label: {
                            Text("Sort")
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "Sort inbox"))
                    .accessibilityHint(String(localized: "Orders the Inbox list. Shortest and Longest use known duration; Title A–Z / Z–A by title; empty or unknown last. Home New preview stays newest-first."))
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            copyInbox()
                        } label: {
                            Label("Copy inbox", systemImage: "doc.plaintext")
                        }
                        // Full Inbox catalog (not podcast/type/UI sort/library search).
                        .disabled(!canExportInbox)
                        .accessibilityLabel(String(localized: "Copy inbox"))
                        .accessibilityHint(
                            String(localized: "Copies the full inbox list to the pasteboard")
                        )

                        ShareLink(
                            item: inboxShareText,
                            subject: Text(String(localized: "Inbox"))
                        ) {
                            Label("Share inbox", systemImage: "square.and.arrow.up")
                        }
                        // Same gates as Copy inbox — full catalog.
                        .disabled(!canExportInbox)
                        .accessibilityLabel(String(localized: "Share inbox"))
                        .accessibilityHint(
                            String(localized: "Opens the system share sheet with the full inbox list")
                        )

                        Button {
                            playRandomEpisode()
                        } label: {
                            Label("Play random", systemImage: "shuffle")
                        }
                        .disabled(playRandomCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Play random"))
                        .accessibilityHint(String(localized: "Plays a random Inbox episode with playable media. Prefers unplayed when any remain."))

                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllInboxCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends Inbox episodes not already queued"))

                        Button {
                            showEnqueueAllUnplayedConfirm = true
                        } label: {
                            Label("Add all unplayed to queue", systemImage: "text.badge.plus")
                        }
                        .disabled(enqueueAllUnplayedInboxCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Add all unplayed to queue"))
                        .accessibilityHint(
                            String(localized: "Appends unplayed, non-archived Inbox episodes not already queued; ignores podcast, episode type, search, and sort filters")
                        )

                        Button {
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        // Full Inbox catalog — not the podcast-chip filtered subset.
                        .disabled(sortedItems.isEmpty)

                        Button {
                            showMarkAllUnplayedConfirm = true
                        } label: {
                            Label("Mark all as unplayed", systemImage: "circle")
                        }
                        // Played episodes are no longer in `inboxEpisodes`; use the full catalog count.
                        .disabled(markAllInboxUnplayedCandidatesCount == 0)
                        .accessibilityHint(
                            String(localized: "Marks played episodes in the full Inbox catalog, including archived episodes")
                        )

                        Button {
                            showArchiveAllConfirm = true
                        } label: {
                            Label("Archive all", systemImage: "archivebox")
                        }
                        // Full Inbox catalog — not the podcast/type-chip filtered subset.
                        .disabled(archiveAllInboxCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Archive all"))
                        .accessibilityHint(
                            String(localized: "Archives non-archived episodes in the full Inbox catalog; ignores podcast, episode type, search, and sort filters")
                        )
                    } label: {
                        Label("Inbox actions", systemImage: "ellipsis.circle")
                    }
                    // Menu stays available when catalog non-empty so Play random / Add all can disable per eligibility.
                    // Disabled while library search replaces Inbox rows (full-catalog actions only).
                    .disabled((sortedItems.isEmpty && markAllInboxUnplayedCandidatesCount == 0) || isSearching)
                    .accessibilityLabel(String(localized: "Inbox actions"))
                    .accessibilityHint(
                        String(localized: "Copy inbox, share inbox, play random, add all to queue, add all unplayed to queue, mark all as played, mark all as unplayed, or archive all")
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
                    store.enqueueAllInbox()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Appends \(enqueueAllInboxCandidatesCount) Inbox episodes to the end of the queue (newest first). Already queued episodes are skipped. Uses the full current-Inbox catalog (same as Mark all as played / Archive all), not library search or the podcast filter. Queue lock does not block enqueue.")
            }
            .confirmationDialog(
                "Add all unplayed to queue?",
                isPresented: $showEnqueueAllUnplayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Add all unplayed to queue") {
                    store.enqueueAllUnplayedInbox()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Appends \(enqueueAllUnplayedInboxCandidatesCount) unplayed, non-archived Inbox episode(s) to the end of the queue (newest first). Already queued, played, and archived episodes are skipped. Uses the full current Inbox catalog, not the podcast, episode type, search, or sort filter. Inbox is already unplayed-only in normal operation, so this may match Add all to queue. Queue lock does not block enqueue.")
            }
            .confirmationDialog(
                "Mark all as played?",
                isPresented: $showMarkAllPlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as played") {
                    store.markAllInboxPlayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Marks \(sortedItems.count) Inbox episodes as played. Episodes leave the Inbox; auto-delete after playing still applies when enabled. Uses the full Inbox catalog (not only the current podcast filter).")
            }
            .confirmationDialog(
                "Mark all as unplayed?",
                isPresented: $showMarkAllUnplayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as unplayed") {
                    store.markAllInboxUnplayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Marks \(markAllInboxUnplayedCandidatesCount) played episodes from the full stored feed catalog behind Inbox as unplayed, including archived episodes. Uses the catalog scope, not the podcast, episode type, search, or sort filter. Does not delete downloads, clear the queue, stop playback, or unarchive episodes.")
            }
            .confirmationDialog(
                "Archive all?",
                isPresented: $showArchiveAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Archive all") {
                    store.archiveAllInbox()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Archives \(archiveAllInboxCandidatesCount) non-archived Inbox episode(s) in the full Inbox catalog (newest first), not the podcast, episode type, search, or sort filter. Archived does not mean played. Does not mark played, delete downloads, or clear the queue.")
            }
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .searchable(text: $searchText, prompt: "Search library")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onAppear {
                releaseInboxPodcastFilterIfFeedGone()
            }
            .onChange(of: store.feeds.map(\.id)) { _, _ in
                releaseInboxPodcastFilterIfFeedGone()
            }
            .onDisappear {
                debounceTask?.cancel()
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

    /// Pasteboard copy of the **full** Inbox catalog (not podcast/type/UI sort/library search). Read-only.
    /// Newest-first store order — same catalog as Mark all as played / Archive all / tab badge; Mark all as unplayed uses its played full-feed scope.
    private func copyInbox() {
        let text = inboxPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Inbox copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does not reorder Inbox or invent queue mutations beyond what `play` already does.
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

/// Filter chip for Inbox podcast chips (mirrors Queue / Downloads).
private struct InboxPodcastFilterChip: View {
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
