import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showDeletePlayedConfirm = false
    @State private var showClearAllConfirm = false
    @State private var showCancelAllConfirm = false
    @State private var showEnqueueAllConfirm = false
    /// Single download pending swipe-delete confirmation (nil = dialog dismissed).
    @State private var episodePendingDelete: PodcastEpisode?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Visible downloaded episodes: played chip → podcast chip → search → sort.
    /// Played chip uses `PodcastStore.isPlayed`. Podcast chip uses feeds present in the
    /// current download set only (never invent). Sort by `AppSettings.downloadsSort`
    /// (date: prefer `downloadedAtEpochMs`, else `pubDateEpochMs`; size: `knownByteSize`;
    /// title: `localizedCaseInsensitiveCompare`, empty last; id tiebreak).
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail / Queue / Favorites / History / Archived), plus
    /// feed display title (`displayTitle(containingEpisodeId:)`). View-only —
    /// Does not mutate `DownloadService.downloads` (tab badge / Play random / Add all / Delete played / Clear all stay full-catalog).
    /// Play random / Add all to queue / Delete played / Clear all / Cancel all stay full-catalog scoped.
    private var filteredDownloads: [DownloadedEpisode] {
        var base = downloads.downloads
        switch settings.downloadsFilter {
        case .all:
            break
        case .unplayed:
            base = base.filter { !store.isPlayed($0.episode.id) }
        case .played:
            base = base.filter { store.isPlayed($0.episode.id) }
        }
        switch podcastFilter {
        case .all:
            break
        case .feed(let feedId):
            base = base.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [DownloadedEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if store.episodeMatchesLibraryQuery(item.episode, query: q) { return true }
                let feedTitle = store.displayTitle(containingEpisodeId: item.episode.id)
                return feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.downloadsSort {
            case .newestFirst:
                let l = lhs.downloadsSortEpochMs ?? Int64.min
                let r = rhs.downloadsSortEpochMs ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                let l = lhs.downloadsSortEpochMs ?? Int64.max
                let r = rhs.downloadsSortEpochMs ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            case .largestFirst:
                // Unknown size last (same honesty as row caption — never invent bytes).
                let l = lhs.knownByteSize() ?? Int64.min
                let r = rhs.knownByteSize() ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .smallestFirst:
                let l = lhs.knownByteSize() ?? Int64.max
                let r = rhs.knownByteSize() ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            case .titleAscending, .titleDescending:
                return downloadsTitleSort(
                    lhs.episode,
                    rhs.episode,
                    ascending: settings.downloadsSort == .titleAscending
                )
            }
        }
    }

    /// Title A–Z / Z–A: empty titles last; id tiebreak.
    private func downloadsTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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
    private var podcastFilter: DownloadsPodcastFilter {
        DownloadsPodcastFilter.fromStorage(settings.downloadsPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one completed download (title A–Z).
    /// Built from the visible download catalog via `feed(containingEpisodeId:)` — never invent.
    private var downloadPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in downloads.downloads {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return feeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var podcastFilterChips: [DownloadsPodcastFilter] {
        var chips: [DownloadsPodcastFilter] = [.all]
        var feeds = downloadPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has downloads)
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

    private func podcastChipTitle(_ chip: DownloadsPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.displayTitle(forFeedId: id)
                ?? downloadPodcastFeeds.first(where: { $0.id == id })?.title
                ?? String(localized: "Podcast")
        }
    }

    private var isFiltering: Bool {
        settings.downloadsFilter != .all
            || isPodcastFiltering
            || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Played offline files eligible for bulk delete (skips favorites — matches auto-delete).
    /// **Global** across the full Downloads catalog — not scoped to the visible chip/search filter
    /// (same honesty as Clear history / Clear favorites / Restore all).
    private var playedDownloadsForDelete: [DownloadedEpisode] {
        downloads.playedDownloadsEligibleForDelete(store: store)
    }

    private var playedDownloadsDeleteSizeLabel: String {
        DownloadStorageUsage.formatBytes(downloads.playedDownloadsEligibleByteSize(store: store))
    }

    /// Full completed catalog size for Clear all confirmation (not chip/search filtered).
    private var clearAllDownloadsSizeLabel: String {
        DownloadStorageUsage.formatBytes(downloads.completedDownloadsByteSize())
    }

    /// Episodes from the **full completed Downloads catalog** (`DownloadService.downloads`,
    /// catalog/persist order — oldest completed first) that are not already queued — same catalog
    /// as Delete played downloads / tab badge, **not** the chip/search filtered list.
    /// Confirm count and `enqueueAllDownloads()` share this eligibility.
    private var enqueueAllDownloadsCandidatesCount: Int {
        downloads.downloads.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Completed Downloads catalog rows with a local playable file on disk via shared
    /// `EpisodePlayRandom` (`.localFileOnly` — `DownloadService.localURL` under Documents/downloads).
    /// Full catalog — **not** played-chip / podcast-chip / searchable filtered.
    /// Distinct from Add all to queue / Delete played / Clear all / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: downloads.downloads.map(\.episode),
            localURL: { downloads.localURL(for: $0) },
            requirement: .localFileOnly
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible completed download is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from tab badge / Add all / Play random / Delete played / Clear all (full catalog).
    private var downloadsRemainingInfoLabel: String? {
        guard !filteredDownloads.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: downloadsRemainingSummary)
    }

    private var downloadsRemainingAccessibilityLabel: String {
        guard let label = downloadsRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Downloads remaining time \(label)")]
        let unknown = downloadsRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var downloadsRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredDownloads.map(\.episode),
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
                if let error = downloads.lastError {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last download failed")
                                    .font(.subheadline.weight(.semibold))
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let latest = downloads.recentErrors.first {
                                    Text(latest.episodeTitle)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    if !latest.feedTitle.isEmpty {
                                        Text(latest.feedTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DownloadsFilter.allCases) { chip in
                                DownloadsFilterChip(
                                    title: chip.label,
                                    selected: settings.downloadsFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Downloads list")
                                ) {
                                    settings.downloadsFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if !downloads.downloads.isEmpty, !downloadPodcastFeeds.isEmpty || isPodcastFiltering {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(podcastFilterChips) { chip in
                                    DownloadsFilterChip(
                                        title: podcastChipTitle(chip),
                                        selected: podcastFilter == chip,
                                        accessibilityHint: String(localized: "Filters the Downloads list by podcast")
                                    ) {
                                        settings.downloadsPodcastFilter = chip.storageValue
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

                // AntennaPod-like downloads info bar (visible filtered list remaining time).
                if let remainingLabel = downloadsRemainingInfoLabel {
                    Section {
                        Text(remainingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(downloadsRemainingAccessibilityLabel)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }

                if downloads.downloads.isEmpty {
                    ContentUnavailableView(
                        "No downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Downloaded episodes will appear here for offline playback.")
                    )
                } else if filteredDownloads.isEmpty {
                    ContentUnavailableView(
                        "No matching downloads",
                        systemImage: "magnifyingglass",
                        description: Text(
                            isFiltering
                                ? String(localized: "No downloads match your filter.")
                                : String(localized: "No downloads match your search.")
                        )
                    )
                } else {
                    Section {
                        ForEach(filteredDownloads) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.episode.title)
                                        .font(.headline)
                                    HStack(spacing: 6) {
                                        Text(item.localFileURL.lastPathComponent)
                                            .lineLimit(1)
                                        if let sizeLabel = item.formattedKnownByteSize {
                                            Text("·")
                                                .accessibilityHidden(true)
                                            Text(sizeLabel)
                                                .monospacedDigit()
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(downloadsRowAccessibilityLabel(for: item))
                                Spacer()
                                Button {
                                    playback.play(episode: item.episode)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(String(localized: "Play"))
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
                                Button(role: .destructive) {
                                    episodePendingDelete = item.episode
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .searchable(text: $searchText, prompt: "Search downloads")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $settings.downloadsSort) {
                            ForEach(DownloadsSort.allCases) { sort in
                                Label(sort.label, systemImage: sort.systemImage)
                                    .tag(sort)
                            }
                        } label: {
                            Text("Sort")
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "Sort downloads"))
                    .accessibilityHint(String(localized: "Orders the Downloads list. Largest and Smallest use known size; Title A–Z / Z–A by title; empty or unknown last. Does not change eviction order."))
                }
                ToolbarItem(placement: .status) {
                    if !downloads.downloads.isEmpty, downloads.storageUsage.fileCount > 0 {
                        Text(downloads.storageUsage.usedFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityLabel(
                                String(localized: "Total downloads size \(downloads.storageUsage.usedFormatted)")
                            )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DownloadErrorsView()
                    } label: {
                        Label("Errors", systemImage: "exclamationmark.bubble")
                    }
                    .accessibilityLabel(String(localized: "Download errors"))
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
                        .accessibilityHint(String(localized: "Plays a random completed download with a local file. Prefers unplayed when any remain."))

                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllDownloadsCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends downloaded episodes not already queued"))

                        Button {
                            showCancelAllConfirm = true
                        } label: {
                            Label("Cancel all downloads", systemImage: "xmark.circle")
                        }
                        .disabled(downloads.cancelAllInFlightCount == 0)
                        .accessibilityHint(String(localized: "Cancels in-progress and waiting downloads without deleting completed files"))

                        Button(role: .destructive) {
                            showDeletePlayedConfirm = true
                        } label: {
                            Label("Delete played downloads", systemImage: "trash")
                        }
                        .disabled(playedDownloadsForDelete.isEmpty)

                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Label("Clear all downloads", systemImage: "trash.fill")
                        }
                        .disabled(downloads.downloads.isEmpty)
                        .accessibilityHint(String(localized: "Deletes every completed offline file including favorites"))
                    } label: {
                        Label("Downloads actions", systemImage: "ellipsis.circle")
                    }
                    // Menu available when completed catalog is non-empty **or** anything is in-flight /
                    // waiting (Cancel all). Play random / Add all / Cancel all / Delete played / Clear all
                    // each disable independently — same honesty as Favorites Play random / Add all + Clear.
                    .disabled(downloads.downloads.isEmpty && downloads.cancelAllInFlightCount == 0)
                }
            }
            .confirmationDialog(
                "Add all to queue?",
                isPresented: $showEnqueueAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Add all to queue") {
                    store.enqueueAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Appends \(enqueueAllDownloadsCandidatesCount) downloaded episodes to the end of the queue (catalog order — oldest completed first). Already queued episodes are skipped. Uses the full Downloads catalog (same as Delete played downloads), not the chip/search filter. Queue lock does not block enqueue.")
            }
            .confirmationDialog(
                "Cancel all downloads?",
                isPresented: $showCancelAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel all downloads") {
                    downloads.cancelAllInFlightDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Cancels \(downloads.cancelAllInFlightCount) in-progress or waiting download(s). Stops active transfers and clears the waiting queue. Does not delete completed offline files."
                )
            }
            .confirmationDialog(
                "Delete played downloads?",
                isPresented: $showDeletePlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete played downloads", role: .destructive) {
                    downloads.deletePlayedDownloads(store: store)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Deletes \(playedDownloadsForDelete.count) played offline file(s) (\(playedDownloadsDeleteSizeLabel)). Keeps unplayed downloads and favorites. Does not mark unplayed, clear the queue, or clear all downloads."
                )
            }
            .confirmationDialog(
                "Clear all downloads?",
                isPresented: $showClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear all downloads", role: .destructive) {
                    downloads.clearAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Deletes \(downloads.downloads.count) completed offline file(s) (\(clearAllDownloadsSizeLabel)), including favorited downloads. Uses the full Downloads catalog — not the chip/search filter. Local files only — keeps played status, queue, favorites list, and history. Distinct from Delete played downloads and from Clear queue."
                )
            }
            .confirmationDialog(
                "Delete download?",
                isPresented: Binding(
                    get: { episodePendingDelete != nil },
                    set: { if !$0 { episodePendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: episodePendingDelete
            ) { episode in
                Button("Delete download", role: .destructive) {
                    downloads.delete(episode)
                    episodePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    episodePendingDelete = nil
                }
            } message: { episode in
                Text(
                    "Delete download for \"\(episode.title)\"? Removes the local offline file only. Keeps played status, queue, and favorites."
                )
            }
        }
    }

    /// VoiceOver: title, size when known, file name.
    private func downloadsRowAccessibilityLabel(for item: DownloadedEpisode) -> String {
        var parts: [String] = [item.episode.title]
        if let sizeLabel = item.formattedKnownByteSize {
            parts.append(String(localized: "Size \(sizeLabel)"))
        }
        parts.append(item.localFileURL.lastPathComponent)
        return parts.joined(separator: ", ")
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` with local file path preferred (`fileURL` from
    /// `DownloadService.localURL`). Resume rules unchanged.
    /// No confirm; does not invent queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = EpisodePlayRandom.pick(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        ) else { return }
        let fileURL = downloads.localURL(for: episode)
        _ = playback.play(episode: episode, fileURL: fileURL)
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

private struct DownloadsFilterChip: View {
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

/// Persisted download failures (ring buffer) with clear action, searchable filter
/// over episode title / feed title / error message (already-saved log only), and
/// per-row **Retry** via existing `DownloadService.download(_:)` when resolvable.
struct DownloadErrorsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var store: PodcastStore
    @State private var showClearConfirmation = false
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full persisted ring buffer — Clear always targets this list (not the filtered subset).
    private var allErrors: [DownloadErrorEntry] {
        downloads.recentErrors
    }

    /// Visible errors; empty query shows the full log. Filters title, feed, and message.
    private var filteredErrors: [DownloadErrorEntry] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allErrors
        if q.isEmpty { return base }
        return base.filter { entry in
            if entry.episodeTitle.localizedCaseInsensitiveContains(q) { return true }
            if entry.feedTitle.localizedCaseInsensitiveContains(q) { return true }
            return entry.message.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            if allErrors.isEmpty {
                ContentUnavailableView(
                    "No download errors",
                    systemImage: "checkmark.circle",
                    description: Text("Failed downloads will appear here (up to \(DownloadService.downloadErrorRingCapacity) recent).")
                )
            } else if filteredErrors.isEmpty {
                ContentUnavailableView(
                    "No matching errors",
                    systemImage: "magnifyingglass",
                    description: Text("No download errors match your search.")
                )
            } else {
                ForEach(filteredErrors) { entry in
                    DownloadErrorRow(entry: entry)
                }
            }
        }
        .navigationTitle("Download errors")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search download errors")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    showClearConfirmation = true
                }
                // Clear always targets the full persisted log (not the filtered subset).
                .disabled(allErrors.isEmpty && downloads.lastError == nil)
            }
        }
        .confirmationDialog(
            "Clear download errors?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear errors", role: .destructive) {
                downloads.clearDownloadErrors()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the saved error log and the Downloads banner. Offline files are kept.")
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

/// One download-error log row with optional **Retry** (existing `DownloadService.download`).
private struct DownloadErrorRow: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var store: PodcastStore
    let entry: DownloadErrorEntry

    private var canRetry: Bool {
        downloads.canRetryDownloadError(entry, store: store)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.episodeTitle.isEmpty ? String(localized: "Unknown episode") : entry.episodeTitle)
                    .font(.headline)
                if !entry.feedTitle.isEmpty {
                    Text(entry.feedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Retry") {
                Task {
                    await downloads.retryDownloadError(entry, store: store)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canRetry)
            .accessibilityLabel(String(localized: "Retry"))
            .accessibilityHint(retryAccessibilityHint)
        }
        .padding(.vertical, 2)
    }

    /// VoiceOver hint — enabled vs disabled (missing / local-folder / in-flight).
    private var retryAccessibilityHint: String {
        if canRetry {
            return String(localized: "Enqueues this episode again via the normal download path")
        }
        if downloads.inProgress.contains(entry.episodeId) {
            return String(localized: "Download already in progress")
        }
        return String(localized: "Episode is no longer in the library or has no downloadable URL")
    }
}
