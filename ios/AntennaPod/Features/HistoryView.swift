import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearHistoryConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showMarkAllPlayedConfirm = false
    @State private var showMarkAllUnplayedConfirm = false
    @State private var showArchiveAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full history catalog (store order: newest last-played first) — Clear history always uses this count.
    private var items: [HistoryEpisode] {
        store.historyEpisodes
    }

    /// Episodes from the **full History catalog** (`store.historyEpisodes`, newest last-played first) that are
    /// not already queued — same catalog as Clear history, **not** the searchable filtered list.
    /// Confirm count and `enqueueAllHistory()` share this eligibility.
    private var enqueueAllHistoryCandidatesCount: Int {
        items.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Unplayed, non-archived episodes in the **full History catalog** — not podcast, search,
    /// or sort filtered. Same archive policy as Favorites / Downloads / All Episodes.
    private var markAllHistoryPlayedCandidatesCount: Int {
        store.markAllHistoryPlayedCandidateCount()
    }

    /// Non-archived episodes in the **full History catalog** — not podcast, search, or sort filtered.
    private var archiveAllHistoryCandidatesCount: Int {
        items.filter { !store.isArchived($0.episode.id) }.count
    }

    /// Played episodes in the **full History catalog** (not podcast/search filter) for Mark all as unplayed.
    /// In-progress unplayed are excluded (already unplayed). Confirm count matches this eligibility.
    private var markAllHistoryUnplayedCandidatesCount: Int {
        items.filter { store.isPlayed($0.episode.id) }.count
    }

    /// History episodes with playable media via shared `EpisodePlayRandom` (local file via
    /// `DownloadService.localURL` — downloads + local-folder `file://` — or streamable http(s)
    /// `downloadUrl`). Full History catalog — **not** podcast-chip or searchable filtered.
    /// Distinct from Clear history / Add all to queue / Mark all as unplayed / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: items.map(\.episode),
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible history episode is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: HistoryPodcastFilter {
        HistoryPodcastFilter.fromStorage(settings.historyPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one history episode.
    /// Built from the History catalog via `feed(containingEpisodeId:)` — never invent.
    /// Order matches the chip label: display title (custom title when set, else RSS title).
    private var historyPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in items {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return historyPodcastsByDisplayTitle(feeds)
    }

    /// A–Z by the name the chip shows. Raw RSS title would place a renamed podcast
    /// where the old name sorts, so the visible label and the row disagree.
    private func historyPodcastsByDisplayTitle(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        feeds.sorted {
            store.displayTitle(for: $0).localizedCaseInsensitiveCompare(
                store.displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    private var podcastFilterChips: [HistoryPodcastFilter] {
        var chips: [HistoryPodcastFilter] = [.all]
        var feeds = historyPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has history)
        // so the user can see why the list is empty and tap All.
        if case .feed(let id) = podcastFilter,
           !feeds.contains(where: { $0.id == id }),
           let feed = store.feeds.first(where: { $0.id == id }) {
            feeds.append(feed)
            feeds = historyPodcastsByDisplayTitle(feeds)
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later History row looks filtered out.
    /// A still-subscribed feed with zero History episodes keeps its chip.
    private func releaseHistoryPodcastFilterIfFeedGone() {
        guard case .feed(let id) = HistoryPodcastFilter.fromStorage(settings.historyPodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.historyPodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: HistoryPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.nonEmptyDisplayTitle(forFeedId: id)
                ?? historyPodcastFeeds.first(where: { $0.id == id }).flatMap { store.nonEmptyDisplayTitle(for: $0) }
                ?? String(localized: "Unknown podcast")
        }
    }

    private var isSearching: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Visible history: podcast chip → search → `historySort`.
    /// Date modes: `HistoryEpisode.lastPlayedAtEpochMs` (`lastPlayedAt`, else `updatedAt` from playback state).
    /// Duration modes: known duration via `EpisodeRemainingTime.knownDurationSeconds`
    /// (feed when known, else saved playback — same path as Queue / Inbox / Favorites / Archived;
    /// never invent; unknown last). Stable tiebreaker episode `id`.
    /// Empty query shows the podcast-filtered list; sort applies to search-filtered results too.
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail / Queue / Favorites), plus
    /// feed title (`HistoryEpisode.feedTitle` = display title). View-only —
    /// Does not mutate `PodcastStore.historyEpisodes` (Home Continue / Clear history stay newest-first catalog).
    /// Clear history / Add all to queue / Mark all as unplayed / Play random stay full-catalog scoped.
    /// Respects history size limit catalog as-is (store already trimmed).
    private var filteredItems: [HistoryEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterPodcast: [HistoryEpisode]
        switch podcastFilter {
        case .all:
            afterPodcast = items
        case .feed(let feedId):
            afterPodcast = items.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        let filtered: [HistoryEpisode]
        if q.isEmpty {
            filtered = afterPodcast
        } else {
            filtered = afterPodcast.filter { item in
                if store.episodeMatchesLibraryQuery(item.episode, query: q) { return true }
                return item.feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.historySort {
            case .newestFirst:
                if lhs.lastPlayedAtEpochMs != rhs.lastPlayedAtEpochMs {
                    return lhs.lastPlayedAtEpochMs > rhs.lastPlayedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.lastPlayedAtEpochMs != rhs.lastPlayedAtEpochMs {
                    return lhs.lastPlayedAtEpochMs < rhs.lastPlayedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .shortestFirst, .longestFirst:
                let shortestFirst = settings.historySort == .shortestFirst
                switch (
                    knownDurationSecondsForHistorySort(lhs.episode),
                    knownDurationSecondsForHistorySort(rhs.episode)
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
                return historyTitleSort(lhs.episode, rhs.episode, ascending: settings.historySort == .titleAscending)
            }
        }
    }

    /// Feed duration when known; else saved playback duration. Never invents a length.
    private func knownDurationSecondsForHistorySort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Title A–Z / Z–A: empty titles last; id tiebreak.
    private func historyTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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

    /// AntennaPod-like info bar: episode count + remaining over the **visible** History list
    /// (podcast chip + searchable filter + sort). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0 (History is mostly played / in-progress — low totals are expected and correct; still
    /// useful for in-progress); **unknown duration skipped** (tilde when any skipped). Currently
    /// playing uses live `PlaybackService` position/duration. Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// Distinct from Clear history / Add all to queue / Mark all as played / Mark all as unplayed / Archive all / Play random / Copy / Share (always full stored catalog). Respects history size
    /// limit catalog as-is — never invents beyond the store-trimmed set.
    private var historyRemainingInfoLabel: String? {
        guard !filteredItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: historyRemainingSummary)
    }

    private var historyRemainingAccessibilityLabel: String {
        guard let label = historyRemainingInfoLabel else { return "" }
        var parts = [String(localized: "History remaining time \(label)")]
        let unknown = historyRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the History remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and that the bar is the podcast+search+sort list.
    private var historyRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The History bar is the visible list after the podcast filter, search, and sort. Sort changes order only. The stored catalog already follows History size, and this bar does not add episodes beyond that stored set. Played episodes that are not currently playing count as zero. It is not the full History catalog behind Clear history, Add all to queue, Mark all as played, Mark all as unplayed, Archive all, Play random, Copy history, or Share history, and not the Home History preview or the Home Continue preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The History bar is the visible list after the podcast filter, search, and sort. Sort changes order only. The stored catalog already follows History size, and this bar does not add episodes beyond that stored set. Played episodes that are not currently playing count as zero. It is not the full History catalog behind Clear history, Add all to queue, Mark all as played, Mark all as unplayed, Archive all, Play random, Copy history, or Share history, and not the Home History preview or the Home Continue preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    /// VoiceOver context for the catalog-empty state versus a podcast/search mismatch.
    /// The visible ContentUnavailableView text stays concise; this value explains the
    /// next useful action without changing History filtering or catalog semantics.
    private var historyEmptyStateAccessibilityValue: String {
        if items.isEmpty {
            return String(localized: "There are no history episodes. Episodes you play or mark as played appear here, ordered by last played.")
        }
        if isPodcastFiltering && !isSearching {
            return String(localized: "The selected podcast has no history episodes. Choose All or another podcast filter.")
        }
        return String(localized: "No history episodes match your search. Clear or change the search to see History.")
    }

    private var historyRemainingSummary: EpisodeRemainingTime.Summary {
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


    /// Plain-text list of the **full** History catalog — not podcast-chip / search / UI sort filtered.
    /// Same honesty as Clear history / Add all to queue / Play random (`store.historyEpisodes`, newest last-played first).
    private var historyPlainText: String {
        HistoryExport.plainText(episodes: items.map(\.episode)) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the full History catalog is non-empty (read-only export).
    private var canExportHistory: Bool {
        !items.isEmpty
    }

    /// “History” header + body for system share sheet (same body as Copy).
    private var historyShareText: String {
        HistoryExport.shareText(episodes: items.map(\.episode)) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }


    var body: some View {
        List {
            if !items.isEmpty, !historyPodcastFeeds.isEmpty || isPodcastFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(podcastFilterChips) { chip in
                                HistoryPodcastFilterChip(
                                    title: podcastChipTitle(chip),
                                    selected: podcastFilter == chip,
                                    accessibilityHint: String(localized: "Filters the History list by podcast")
                                ) {
                                    settings.historyPodcastFilter = chip.storageValue
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

            // AntennaPod-like history info bar (visible sorted+podcast+search filtered list remaining time).
            // Hidden when catalog empty or filters match nothing — not full-catalog Clear count.
            // Played (not current) → 0; totals may often be low — still useful for in-progress.
            if let remainingLabel = historyRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(historyRemainingAccessibilityLabel)
                        .accessibilityHint(historyRemainingAccessibilityHint)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Episodes you play or mark as played appear here, ordered by last played.")
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No history yet"))
                .accessibilityValue(historyEmptyStateAccessibilityValue)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching history",
                    systemImage: "magnifyingglass",
                    description: Text(
                        isPodcastFiltering && !isSearching
                            ? String(localized: "No history matches your filter.")
                            : String(localized: "No history matches your search.")
                    )
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No matching history"))
                .accessibilityValue(historyEmptyStateAccessibilityValue)
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Last played")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.removeFromHistory(item.episode.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
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
                    }
                }
                if let limit = settings.historySizeLimit.entryLimit {
                    Section {
                        Text(
                            String(
                                localized: "History is capped at \(limit) episodes (Settings → Library → History size). Oldest last-played entries are removed first."
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(
                                localized: "History is capped at \(limit) episodes (Settings → Library → History size). Oldest last-played entries are removed first."
                            )
                        )
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search history")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onAppear {
            releaseHistoryPodcastFilterIfFeedGone()
        }
        .onChange(of: store.feeds.map(\.id)) { _, _ in
            releaseHistoryPodcastFilterIfFeedGone()
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.historySort) {
                        ForEach(HistorySort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort history"))
                .accessibilityHint(String(localized: "Orders the History list. Shortest and Longest use known duration; Title A–Z / Z–A by title; empty or unknown last. Home Continue preview stays newest-first."))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyHistory()
                    } label: {
                        Label("Copy history", systemImage: "doc.plaintext")
                    }
                    // Full History catalog (not podcast/search/UI sort).
                    .disabled(!canExportHistory)
                    .accessibilityLabel(String(localized: "Copy history"))
                    .accessibilityHint(
                        String(localized: "Copies the full history list to the pasteboard")
                    )

                    ShareLink(
                        item: historyShareText,
                        subject: Text(String(localized: "History"))
                    ) {
                        Label("Share history", systemImage: "square.and.arrow.up")
                    }
                    // Same gates as Copy history — full catalog.
                    .disabled(!canExportHistory)
                    .accessibilityLabel(String(localized: "Share history"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the full history list")
                    )

                    Button {
                        playRandomEpisode()
                    } label: {
                        Label("Play random", systemImage: "shuffle")
                    }
                    .disabled(playRandomCandidates.isEmpty)
                    .accessibilityLabel(String(localized: "Play random"))
                    .accessibilityHint(String(localized: "Plays a random history episode with playable media. Prefers unplayed when any remain."))

                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllHistoryCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Appends history episodes not already queued"))

                    Button {
                        showMarkAllPlayedConfirm = true
                    } label: {
                        Label("Mark all as played", systemImage: "checkmark.circle")
                    }
                    .disabled(markAllHistoryPlayedCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Marks unplayed, non-archived episodes in the full History catalog as played; ignores podcast, search, and sort filters")
                    )

                    Button {
                        showMarkAllUnplayedConfirm = true
                    } label: {
                        Label("Mark all as unplayed", systemImage: "circle")
                    }
                    .disabled(markAllHistoryUnplayedCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Marks played History episodes as unplayed; leaves History when no progress remains"))

                    Button {
                        showArchiveAllConfirm = true
                    } label: {
                        Label("Archive all", systemImage: "archivebox")
                    }
                    .disabled(archiveAllHistoryCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Archives non-archived episodes in the full History catalog; ignores podcast, search, and sort filters")
                    )

                    Button(role: .destructive) {
                        showClearHistoryConfirm = true
                    } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                    // Clear always targets the full history list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("History actions", systemImage: "ellipsis.circle")
                }
                // Menu stays available when catalog non-empty so Play random / Add all can disable per eligibility.
                .disabled(items.isEmpty)
                .accessibilityLabel(String(localized: "History actions"))
                .accessibilityHint(
                    String(localized: "Copy history, share history, play random, add all to queue, mark all as played, mark all as unplayed, archive all, or clear history")
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
                store.enqueueAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllHistoryCandidatesCount) history episodes to the end of the queue (newest last-played first). Already queued episodes are skipped. Uses the full History catalog (same as Clear history), not the podcast or searchable filter. Queue lock does not block enqueue.")
        }
        .confirmationDialog(
            "Mark all as played?",
            isPresented: $showMarkAllPlayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as played") {
                store.markAllHistoryPlayed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks \(markAllHistoryPlayedCandidatesCount) unplayed, non-archived History episode(s) as played. Uses the full History catalog (newest last-played first), not the podcast, search, or sort filter. Auto-delete after playing still applies when enabled; this does not clear History, remove episodes from the catalog, or delete downloads itself.")
        }
        .confirmationDialog(
            "Mark all as unplayed?",
            isPresented: $showMarkAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as unplayed") {
                store.markAllHistoryUnplayed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks \(markAllHistoryUnplayedCandidatesCount) played episodes in History as unplayed (full catalog, not podcast or search filter). Episodes leave History when no progress remains — same as per-row Mark unplayed. Does not delete downloads, clear the queue, or stop playback.")
        }
        .confirmationDialog(
            "Archive all?",
            isPresented: $showArchiveAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive all") {
                store.archiveAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archives \(archiveAllHistoryCandidatesCount) non-archived History episode(s) in the full History catalog (newest last-played first), not the podcast, search, or sort filter. Archived does not mean played. Does not mark played, delete downloads, or clear the queue.")
        }
        .confirmationDialog(
            "Clear history?",
            isPresented: $showClearHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                store.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(items.count) episodes from history. Does not unsubscribe, delete downloads, or clear the queue.")
        }
    }

    /// Pasteboard copy of the **full** History catalog (not podcast/search/UI sort). Read-only.
    private func copyHistory() {
        let text = historyPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "History copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does not reorder History or invent queue mutations beyond what `play` already does.
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

