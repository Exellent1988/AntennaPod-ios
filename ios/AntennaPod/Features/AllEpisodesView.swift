import SwiftUI

struct AllEpisodesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService
    @State private var searchText = ""
    @State private var showEnqueueAllConfirm = false

    /// Soft-capped catalog (`store.allEpisodes`, newest-500) — Add all to queue always uses this,
    /// **not** the chip/podcast/search filtered visible list (`items`).
    private var catalogItems: [InboxEpisode] {
        store.allEpisodes
    }

    /// Episodes from the **soft-capped All Episodes catalog** (`store.allEpisodes`, newest 500 by
    /// `pubDateEpochMs`) that are not already queued — same catalog as the list’s soft cap,
    /// **not** chip (`allEpisodesFilter`), podcast chip, or searchable filter.
    /// Confirm count and `enqueueAllEpisodes()` share this eligibility.
    /// **Soft-cap honesty:** never claims eligibility beyond the newest-500 set.
    private var enqueueAllEpisodesCandidatesCount: Int {
        catalogItems.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Soft-capped All Episodes catalog episodes with playable media via shared
    /// `EpisodePlayRandom` (local file via `DownloadService.localURL` — downloads + local-folder
    /// `file://` — or streamable http(s) `downloadUrl`). Same newest-500 set as Add all
    /// (`store.allEpisodes`) — **not** status/podcast/type/search filtered. **Soft-cap honesty:**
    /// never invents eligibility beyond the capped catalog. Distinct from Add all / remaining-time
    /// visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: catalogItems.map(\.episode),
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible capped episode is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: AllEpisodesPodcastFilter {
        AllEpisodesPodcastFilter.fromStorage(settings.allEpisodesPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one episode in the soft-capped All Episodes
    /// catalog (title A–Z). Built via `feed(containingEpisodeId:)` — never invent.
    private var allEpisodesPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in catalogItems {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return feeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var podcastFilterChips: [AllEpisodesPodcastFilter] {
        var chips: [AllEpisodesPodcastFilter] = [.all]
        var feeds = allEpisodesPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer appears in the
        // soft-capped set) so the user can see why the list is empty and tap All.
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

    private func podcastChipTitle(_ chip: AllEpisodesPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            if let shown = store.displayTitle(forFeedId: id) {
                return shown
            }
            if let feed = allEpisodesPodcastFeeds.first(where: { $0.id == id }) {
                return store.displayTitle(for: feed)
            }
            return String(localized: "Podcast")
        }
    }

    /// Soft cap first (newest 500 via `store.allEpisodes`), then sort → status → podcast → type → search.
    /// **Honesty:** `store.allEpisodes` is already the newest-500 by `pubDateEpochMs`.
    /// Oldest / Shortest / Longest / Title A–Z / Title Z–A only reorder within that capped set — they do
    /// **not** pull older episodes from beyond the soft limit. Missing dates / unknown durations /
    /// empty titles sort last; stable tiebreaker is episode `id` (same as Inbox). Orphan episodes
    /// (missing feed) match **All** only.
    private var items: [InboxEpisode] {
        var base = store.allEpisodes.sorted { lhs, rhs in
            switch settings.allEpisodesSort {
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
                let shortestFirst = settings.allEpisodesSort == .shortestFirst
                switch (
                    knownDurationSecondsForAllEpisodesSort(lhs.episode),
                    knownDurationSecondsForAllEpisodesSort(rhs.episode)
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
                return allEpisodesTitleSort(lhs.episode, rhs.episode, ascending: settings.allEpisodesSort == .titleAscending)
            }
        }
        switch settings.allEpisodesFilter {
        case .all:
            break
        case .unplayed:
            // Same spirit as Inbox: not played and not archived, but only within the capped set.
            base = base.filter { !store.isPlayed($0.episode.id) && !store.isArchived($0.episode.id) }
        case .downloaded:
            base = base.filter { downloads.isDownloaded($0.episode) }
        case .favorites:
            // Starred via PodcastStore.isFavorite / favorites.json — still within the capped set.
            base = base.filter { store.isFavorite($0.episode.id) }
        }
        switch podcastFilter {
        case .all:
            break
        case .feed(let feedId):
            base = base.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        if settings.allEpisodesEpisodeTypeFilter != .all {
            base = base.filter { settings.allEpisodesEpisodeTypeFilter.matches($0.episode) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { item in
            item.episode.title.localizedCaseInsensitiveContains(q)
                || item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    /// Type chips for the soft-capped All Episodes catalog (before status/podcast/type/search).
    private var episodeTypeFilterChips: [EpisodeTypeFilter] {
        EpisodeTypeFilter.chips(
            presentIn: catalogItems.map(\.episode),
            selected: settings.allEpisodesEpisodeTypeFilter
        )
    }

    private var showEpisodeTypeFilterChips: Bool {
        EpisodeTypeFilter.shouldShowChipRow(
            presentIn: catalogItems.map(\.episode),
            selected: settings.allEpisodesEpisodeTypeFilter
        )
    }

    private var isFiltering: Bool {
        settings.allEpisodesFilter != .all
            || isPodcastFiltering
            || settings.allEpisodesEpisodeTypeFilter != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** All Episodes list
    /// (soft cap newest-500 → sort → status → podcast → type → search). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes
    /// full duration; **played** (not current) → 0; **unknown duration skipped** (tilde when
    /// any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// **Soft-cap honesty:** never claims remaining beyond the capped+filtered visible set.
    private var allEpisodesRemainingInfoLabel: String? {
        guard !items.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: allEpisodesRemainingSummary)
    }

    private var allEpisodesRemainingAccessibilityLabel: String {
        guard let label = allEpisodesRemainingInfoLabel else { return "" }
        var parts = [String(localized: "All Episodes remaining time \(label)")]
        let unknown = allEpisodesRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var allEpisodesRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: items.map(\.episode),
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

    /// Feed duration when known; else saved playback duration. Never invents a length.
    /// Same known-duration path as Queue / Feed detail duration sort (no live player).
    private func knownDurationSecondsForAllEpisodesSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Title A–Z / Z–A within soft-capped set: empty titles last; id tiebreak.
    private func allEpisodesTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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


    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AllEpisodesFilter.allCases) { chip in
                            AllEpisodesFilterChip(
                                title: chip.label,
                                selected: settings.allEpisodesFilter == chip,
                                accessibilityHint: String(localized: "Filters the All Episodes list")
                            ) {
                                settings.allEpisodesFilter = chip
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if !catalogItems.isEmpty, !allEpisodesPodcastFeeds.isEmpty || isPodcastFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(podcastFilterChips) { chip in
                                AllEpisodesFilterChip(
                                    title: podcastChipTitle(chip),
                                    selected: podcastFilter == chip,
                                    accessibilityHint: String(localized: "Filters the All Episodes list by podcast")
                                ) {
                                    settings.allEpisodesPodcastFilter = chip.storageValue
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

            // itunes:episodeType chips — within soft-capped catalog; hide when no types present.
            if !catalogItems.isEmpty, showEpisodeTypeFilterChips {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(episodeTypeFilterChips) { chip in
                                AllEpisodesFilterChip(
                                    title: chip.label,
                                    selected: settings.allEpisodesEpisodeTypeFilter == chip,
                                    accessibilityHint: String(localized: "Filters the All Episodes list by episode type")
                                ) {
                                    settings.allEpisodesEpisodeTypeFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            // AntennaPod-like All Episodes info bar (visible soft-capped+filtered list remaining time).
            // Soft-cap honesty: sums only the newest-500 → sort → status → podcast → type → search set — never beyond.
            if let remainingLabel = allEpisodesRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(allEpisodesRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                if isFiltering {
                    ContentUnavailableView(
                        "No matching episodes",
                        systemImage: "magnifyingglass",
                        description: Text("No episodes match your filter.")
                    )
                } else {
                    ContentUnavailableView(
                        "No episodes yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Episodes from your subscriptions appear here, newest first.")
                    )
                }
            } else {
                ForEach(items) { item in
                    EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.toggleArchived(item.episode.id)
                            } label: {
                                Label(
                                    store.isArchived(item.episode.id)
                                        ? String(localized: "Restore")
                                        : String(localized: "Archive"),
                                    systemImage: store.isArchived(item.episode.id)
                                        ? "arrow.uturn.backward" : "archivebox"
                                )
                            }
                            .tint(store.isArchived(item.episode.id) ? .green : .orange)
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
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.allEpisodesSort) {
                        ForEach(AllEpisodesSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort all episodes"))
                .accessibilityValue(settings.allEpisodesSort.label)
                .accessibilityHint(String(localized: "Orders the All Episodes list within the newest-500 soft cap. Shortest and Longest use known duration; Title A–Z / Z–A by title; empty or unknown last. Does not pull older episodes beyond the cap."))
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
                    .accessibilityHint(String(localized: "Plays a random All Episodes catalog episode with playable media within the newest-500 soft cap. Prefers unplayed when any remain."))

                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllEpisodesCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Appends All Episodes not already queued (newest 500 soft cap)"))
                } label: {
                    Label("Episodes actions", systemImage: "ellipsis.circle")
                }
                // Menu stays available when soft-capped catalog non-empty so Play random / Add all can disable per eligibility.
                .disabled(catalogItems.isEmpty)
            }
        }
        .searchable(text: $searchText, prompt: "Filter by title or podcast")
        .confirmationDialog(
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllEpisodes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllEpisodesCandidatesCount) episodes to the end of the queue (newest first within the newest-500 soft cap). Already queued episodes are skipped. Uses the soft-capped All Episodes catalog (newest 500 by publish date), not the status, podcast, type, or search filter. Queue lock does not block enqueue.")
        }
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; soft-capped newest-500 catalog only — does **not** invent episodes beyond the cap;
    /// no invented queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = EpisodePlayRandom.pick(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        ) else { return }
        _ = playback.play(episode: episode)
    }
}

private struct AllEpisodesFilterChip: View {
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
