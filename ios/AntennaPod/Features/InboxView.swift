import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showMarkAllPlayedConfirm = false
    @State private var showEnqueueAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full Inbox catalog ordered by `AppSettings.inboxSort`.
    /// Date modes: `pubDateEpochMs` (missing last). Duration modes: known duration via
    /// `EpisodeRemainingTime.knownDurationSeconds` (feed when known, else saved playback —
    /// same path as Queue / Feed / All Episodes; never invent; unknown last).
    /// Title modes: `localizedCaseInsensitiveCompare` (empty titles last).
    /// Stable tiebreaker is episode `id` (no `dateAdded` on `PodcastEpisode`).
    /// Does not mutate `PodcastStore.inboxEpisodes` (Home New preview stays newest-first).
    /// Used for bulk Mark all / Archive all counts.
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

    /// Unique feeds that currently have at least one Inbox episode (title A–Z).
    /// Built from the Inbox catalog via `feed(containingEpisodeId:)` — never invent.
    private var inboxPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in store.inboxEpisodes {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return feeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
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
            feeds.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    private func podcastChipTitle(_ chip: InboxPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.feeds.first(where: { $0.id == id })?.title
                ?? inboxPodcastFeeds.first(where: { $0.id == id })?.title
                ?? String(localized: "Podcast")
        }
    }

    /// Visible Inbox rows: `inboxSort` → podcast chip → itunes:episodeType chip.
    /// Library `.searchable` replaces this list entirely (`LibrarySearchResultsView`).
    /// View-only — Mark all / Add all to queue / Archive all / Play random stay full-catalog scoped.
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

    /// Inbox episodes with playable media (local file via `DownloadService.localURL` —
    /// downloads + local-folder `file://` — or streamable http(s) `downloadUrl`).
    /// Full Inbox catalog — **not** podcast-chip, episode-type, or library-search filtered.
    /// Distinct from Mark all / Add all to queue / Archive all / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        store.inboxEpisodes.map(\.episode).filter { episodeHasPlayableMedia($0) }
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible.
    /// Inbox is already unplayed-only (`!isPlayed` && not archived), so prefer-unplayed is a no-op
    /// in practice — same helper pattern as History / Favorites / Feed / Queue / Downloads.
    private var playRandomCandidates: [PodcastEpisode] {
        let eligible = playRandomEligibleEpisodes
        let unplayed = eligible.filter { !store.isPlayed($0.id) }
        return unplayed.isEmpty ? eligible : unplayed
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
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from tab badge / Mark all / Add all / Archive all / Play random (full catalog).
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
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        // Full Inbox catalog — not the podcast-chip filtered subset.
                        .disabled(sortedItems.isEmpty)

                        Button {
                            store.archiveAllInbox()
                        } label: {
                            Label("Archive all", systemImage: "archivebox")
                        }
                        // Full Inbox catalog — not the podcast-chip filtered subset.
                        .disabled(sortedItems.isEmpty)
                    } label: {
                        Label("Inbox actions", systemImage: "ellipsis.circle")
                    }
                    // Menu stays available when catalog non-empty so Play random / Add all can disable per eligibility.
                    .disabled(sortedItems.isEmpty || isSearching)
                }
            }
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
                Text("Appends \(enqueueAllInboxCandidatesCount) Inbox episodes to the end of the queue (newest first). Already queued episodes are skipped. Uses the full Inbox catalog (same as Mark all / Archive all), not library search or the podcast filter. Queue lock does not block enqueue.")
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
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .searchable(text: $searchText, prompt: "Search library")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
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

    /// Local download / local-folder file, or streamable http(s) enclosure — same honesty as
    /// History / Favorites / Feed detail Play random / `PlaybackService.resolvePlaybackURL` inputs (Wi‑Fi stream gate still applies at play time).
    private func episodeHasPlayableMedia(_ episode: PodcastEpisode) -> Bool {
        if downloads.localURL(for: episode) != nil { return true }
        guard let raw = episode.downloadUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw) else { return false }
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// Uniform pick among `playRandomCandidates`; starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does not reorder Inbox or invent queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = playRandomCandidates.randomElement() else { return }
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
