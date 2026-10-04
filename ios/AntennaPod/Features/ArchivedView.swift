import SwiftUI
import UIKit

struct ArchivedView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showRestoreAllConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

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

    /// Archived episodes with playable media via shared `EpisodePlayRandom` (local file via
    /// `DownloadService.localURL` — downloads + local-folder `file://` — or streamable http(s)
    /// `downloadUrl`). Full Archived catalog — **not** podcast-chip or searchable filtered.
    /// Distinct from Restore all / Add all to queue / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: items.map(\.episode),
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible archived episode is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
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

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later Archived row looks filtered out.
    /// A still-subscribed feed with zero Archived episodes keeps its chip.
    private func releaseArchivedPodcastFilterIfFeedGone() {
        guard case .feed(let id) = ArchivedPodcastFilter.fromStorage(settings.archivedPodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.archivedPodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: ArchivedPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.nonEmptyDisplayTitle(forFeedId: id)
                ?? archivedPodcastFeeds.first(where: { $0.id == id }).flatMap { store.nonEmptyDisplayTitle(for: $0) }
                ?? String(localized: "Unknown podcast")
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
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail / Queue / Favorites / History), plus
    /// feed title (`ArchivedEpisode.feedTitle` = display title). View-only —
    /// Does not mutate `PodcastStore.archivedEpisodes` (Restore all counts stay on newest-first catalog).
    /// Restore all / Add all to queue / Play random stay full-catalog scoped.
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
                if store.episodeMatchesLibraryQuery(item.episode, query: q) { return true }
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
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from Restore all / Add all to queue / Play random eligibility (always full catalog).
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

    /// VoiceOver hint for the Archived remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and that the bar is the podcast+search+sort list.
    /// Archive does not mean played. Distinct from Restore all / Add all to queue /
    /// Play random / Copy archived / Share archived (full catalog) and the Home Archived preview.
    private var archivedRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Archived bar is the visible list after the podcast filter, search, and sort. Sort changes order only. Archive does not mean played. Played episodes that are not currently playing count as zero. It is not the full Archived catalog behind Restore all, Add all to queue, Play random, Copy archived, or Share archived, and not the Home Archived preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the Feed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Archived bar is the visible list after the podcast filter, search, and sort. Sort changes order only. Archive does not mean played. Played episodes that are not currently playing count as zero. It is not the full Archived catalog behind Restore all, Add all to queue, Play random, Copy archived, or Share archived, and not the Home Archived preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, the Feed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    /// VoiceOver context for the catalog-empty state versus a podcast/search mismatch.
    /// The visible ContentUnavailableView text stays concise; this value explains the
    /// next useful action without changing Archived filtering or catalog semantics.
    private var archivedEmptyStateAccessibilityValue: String {
        if items.isEmpty {
            return String(localized: "There are no archived episodes. Archive hides episodes from Inbox without marking them played. Restore them here or from a feed.")
        }
        if isPodcastFiltering && !isSearching {
            return String(localized: "The selected podcast has no archived episodes. Choose All or another podcast filter.")
        }
        return String(localized: "No archived episodes match your search. Clear or change the search to see Archived.")
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


    /// Plain-text list of the **full** Archived catalog — not podcast-chip / search / UI sort filtered.
    /// Same honesty as Restore all / Add all to queue / Play random (`store.archivedEpisodes`, newest archived first).
    private var archivedPlainText: String {
        ArchivedExport.plainText(episodes: items.map(\.episode)) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the full Archived catalog is non-empty (read-only export).
    private var canExportArchived: Bool {
        !items.isEmpty
    }

    /// “Archived” header + body for system share sheet (same body as Copy).
    private var archivedShareText: String {
        ArchivedExport.shareText(episodes: items.map(\.episode)) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
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
                        .accessibilityHint(archivedRemainingAccessibilityHint)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No archived episodes",
                    systemImage: "archivebox",
                    description: Text("Archive hides episodes from Inbox without marking them played. Restore them here or from a feed.")
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No archived episodes"))
                .accessibilityValue(archivedEmptyStateAccessibilityValue)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No matching archived"))
                .accessibilityValue(archivedEmptyStateAccessibilityValue)
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
        .onAppear {
            releaseArchivedPodcastFilterIfFeedGone()
        }
        .onChange(of: store.feeds.map(\.id)) { _, _ in
            releaseArchivedPodcastFilterIfFeedGone()
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
                        copyArchived()
                    } label: {
                        Label("Copy archived", systemImage: "doc.plaintext")
                    }
                    // Full Archived catalog (not podcast/search/UI sort).
                    .disabled(!canExportArchived)
                    .accessibilityLabel(String(localized: "Copy archived"))
                    .accessibilityHint(
                        String(localized: "Copies the full archived list to the pasteboard")
                    )

                    ShareLink(
                        item: archivedShareText,
                        subject: Text(String(localized: "Archived"))
                    ) {
                        Label("Share archived", systemImage: "square.and.arrow.up")
                    }
                    // Same gates as Copy archived — full catalog.
                    .disabled(!canExportArchived)
                    .accessibilityLabel(String(localized: "Share archived"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the full archived list")
                    )

                    Button {
                        playRandomEpisode()
                    } label: {
                        Label("Play random", systemImage: "shuffle")
                    }
                    .disabled(playRandomCandidates.isEmpty)
                    .accessibilityLabel(String(localized: "Play random"))
                    .accessibilityHint(String(localized: "Plays a random archived episode with playable media. Prefers unplayed when any remain."))

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
                // Menu stays available when catalog non-empty so Play random / Add all can disable per eligibility.
                .disabled(items.isEmpty)
                .accessibilityLabel(String(localized: "Archived actions"))
                .accessibilityHint(
                    String(localized: "Copy archived, share archived, play random, add all to queue, or restore all")
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

    /// Pasteboard copy of the **full** Archived catalog (not podcast/search/UI sort). Read-only.
    private func copyArchived() {
        let text = archivedPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Archived copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does **not** unarchive / restore or reorder Archived; no invented queue mutations beyond what `play` already does.
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
