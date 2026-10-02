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
            return store.feeds.first(where: { $0.id == id })?.title
                ?? allEpisodesPodcastFeeds.first(where: { $0.id == id })?.title
                ?? String(localized: "Podcast")
        }
    }

    /// Soft cap first (newest 500 via `store.allEpisodes`), then sort → status chip → podcast → search.
    /// **Honesty:** `store.allEpisodes` is already the newest-500 by `pubDateEpochMs`.
    /// Oldest / Shortest / Longest only reorder within that capped set — they do **not** pull older
    /// episodes from beyond the soft limit. Missing dates / unknown durations sort last; stable
    /// tiebreaker is episode `id` (same as Inbox). Orphan episodes (missing feed) match **All** only.
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
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { item in
            item.episode.title.localizedCaseInsensitiveContains(q)
                || item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private var isFiltering: Bool {
        settings.allEpisodesFilter != .all
            || isPodcastFiltering
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** All Episodes list
    /// (soft cap newest-500 → sort → status chip → podcast → search). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes
    /// full duration; **played** (not current) → 0; **unknown duration skipped** (tilde when
    /// any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide).
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
            savedPositionSeconds: { store.positionSeconds(for: $0) }
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

            // AntennaPod-like All Episodes info bar (visible soft-capped+filtered list remaining time).
            // Soft-cap honesty: sums only the newest-500 → sort → status → podcast → search set — never beyond.
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
                .accessibilityHint(String(localized: "Orders the All Episodes list within the newest-500 soft cap. Shortest and Longest use known duration; unknown last. Does not pull older episodes beyond the cap."))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
                // Menu enabled whenever soft-capped catalog is non-empty (even if chip/podcast/search hides rows).
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
            Text("Appends \(enqueueAllEpisodesCandidatesCount) episodes to the end of the queue (newest first within the newest-500 soft cap). Already queued episodes are skipped. Uses the soft-capped All Episodes catalog (newest 500 by publish date), not the chip, podcast, or search filter. Queue lock does not block enqueue.")
        }
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
