import SwiftUI

struct ArchivedView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showRestoreAllConfirm = false
    @State private var showEnqueueAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full archived catalog (store order: newest archived first) — Restore all always uses this count.
    private var items: [ArchivedEpisode] {
        store.archivedEpisodes
    }

    /// Episodes from the **full Archived catalog** (`store.archivedEpisodes`, newest archived first) that are
    /// not already queued — same catalog as Restore all, **not** the podcast-chip or searchable filtered list.
    /// Confirm count and `enqueueAllArchived()` share this eligibility.
    /// Does **not** restore / unarchive.
    private var enqueueAllArchivedCandidatesCount: Int {
        items.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: ArchivedPodcastFilter {
        ArchivedPodcastFilter.fromStorage(settings.archivedPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one archived episode (title A–Z).
    /// Built from the Archived catalog via `feed(containingEpisodeId:)` — never invent.
    private var archivedPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in items {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return feeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var podcastFilterChips: [ArchivedPodcastFilter] {
        var chips: [ArchivedPodcastFilter] = [.all]
        var feeds = archivedPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has archived
        // episodes) so the user can see why the list is empty and tap All.
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

    private func podcastChipTitle(_ chip: ArchivedPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.feeds.first(where: { $0.id == id })?.title
                ?? archivedPodcastFeeds.first(where: { $0.id == id })?.title
                ?? String(localized: "Podcast")
        }
    }

    private var isSearching: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Visible archived: podcast chip → search → `archivedSort`.
    /// Date modes: `ArchivedEpisode.archivedAtEpochMs` (`archivedAtById` / `archived.json`).
    /// Duration modes: known duration via `EpisodeRemainingTime.knownDurationSeconds`
    /// (feed when known, else saved playback — same path as Queue / Inbox / Favorites / History;
    /// never invent; unknown last). Stable tiebreaker episode `id`.
    /// Empty query shows the podcast-filtered list; sort applies to search-filtered results too.
    /// Does not mutate `PodcastStore.archivedEpisodes` (Restore all counts stay on newest-first catalog).
    /// View-only — Restore all / Add all to queue stay full-catalog scoped.
    private var filteredItems: [ArchivedEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterPodcast: [ArchivedEpisode]
        switch podcastFilter {
        case .all:
            afterPodcast = items
        case .feed(let feedId):
            afterPodcast = items.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        let filtered: [ArchivedEpisode]
        if q.isEmpty {
            filtered = afterPodcast
        } else {
            filtered = afterPodcast.filter { item in
                if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
                return item.feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.archivedSort {
            case .newestFirst:
                if lhs.archivedAtEpochMs != rhs.archivedAtEpochMs {
                    return lhs.archivedAtEpochMs > rhs.archivedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.archivedAtEpochMs != rhs.archivedAtEpochMs {
                    return lhs.archivedAtEpochMs < rhs.archivedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .shortestFirst, .longestFirst:
                let shortestFirst = settings.archivedSort == .shortestFirst
                switch (
                    knownDurationSecondsForArchivedSort(lhs.episode),
                    knownDurationSecondsForArchivedSort(rhs.episode)
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
                return archivedTitleSort(lhs.episode, rhs.episode, ascending: settings.archivedSort == .titleAscending)
            }
        }
    }

    /// Feed duration when known; else saved playback duration. Never invents a length.
    private func knownDurationSecondsForArchivedSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Title A–Z / Z–A: empty titles last; id tiebreak.
    private func archivedTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Archived list
    /// (podcast chip + searchable filter + sort). **Honesty:** archived ≠ played — use normal
    /// duration−position rules (not “archived means finished”). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes
    /// full duration; **played** (not current) → 0; **unknown duration skipped** (tilde when
    /// any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from Restore all count (always full catalog).
    private var archivedRemainingInfoLabel: String? {
        guard !filteredItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: archivedRemainingSummary)
    }

    private var archivedRemainingAccessibilityLabel: String {
        guard let label = archivedRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Archived remaining time \(label)")]
        let unknown = archivedRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var archivedRemainingSummary: EpisodeRemainingTime.Summary {
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


    var body: some View {
        List {
            if !items.isEmpty, !archivedPodcastFeeds.isEmpty || isPodcastFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(podcastFilterChips) { chip in
                                ArchivedPodcastFilterChip(
                                    title: podcastChipTitle(chip),
                                    selected: podcastFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Archived list by podcast")
                                ) {
                                    settings.archivedPodcastFilter = chip.storageValue
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

            // AntennaPod-like archived info bar (visible sorted+podcast+search filtered list remaining time).
            // Hidden when catalog empty or filters match nothing — not full-catalog Restore all count.
            // Archived ≠ played; played (not current) → 0 via normal rules.
            if let remainingLabel = archivedRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(archivedRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No archived episodes",
                    systemImage: "archivebox",
                    description: Text("Archive hides episodes from Inbox without marking them played. Restore them here or from a feed.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching archived",
                    systemImage: "magnifyingglass",
                    description: Text(
                        isPodcastFiltering && !isSearching
                            ? String(localized: "No archived episodes match your filter.")
                            : String(localized: "No archived episodes match your search.")
                    )
                )
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.archivedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Archived")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            store.restore(item.episode.id)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search archived")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.archivedSort) {
                        ForEach(ArchivedSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort archived"))
                .accessibilityHint(String(localized: "Orders the Archived list. Shortest and Longest use known duration; Title A–Z / Z–A by title; empty or unknown last. Restore all stays full catalog."))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllArchivedCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Appends archived episodes not already queued"))

                    Button {
                        showRestoreAllConfirm = true
                    } label: {
                        Label("Restore all", systemImage: "arrow.uturn.backward")
                    }
                    // Restore all always targets the full archived list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("Archived actions", systemImage: "ellipsis.circle")
                }
                .disabled(items.isEmpty)
            }
        }
        .confirmationDialog(
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllArchived()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllArchivedCandidatesCount) archived episodes to the end of the queue (newest archived first). Already queued episodes are skipped. Uses the full Archived catalog (same as Restore all), not the podcast or searchable filter. Does not restore or unarchive. Queue lock does not block enqueue.")
        }
        .confirmationDialog(
            "Restore all?",
            isPresented: $showRestoreAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore all") {
                store.restoreAllArchived()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores \(items.count) archived episodes. Does not mark unplayed or delete downloads.")
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

/// Filter chip for Archived podcast chips (mirrors Favorites / History / Inbox).
private struct ArchivedPodcastFilterChip: View {
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
