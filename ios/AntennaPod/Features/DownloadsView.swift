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
    @State private var showEnqueueAllConfirm = false
    /// Single download pending swipe-delete confirmation (nil = dialog dismissed).
    @State private var episodePendingDelete: PodcastEpisode?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Visible downloaded episodes: chip filter → search → sort.
    /// Chip uses `PodcastStore.isPlayed`. Sort by `AppSettings.downloadsSort`
    /// (prefer `downloadedAtEpochMs`, else `pubDateEpochMs`).
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
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [DownloadedEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
                let feedTitle = store.feed(containingEpisodeId: item.episode.id)?.title ?? ""
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
            }
        }
    }

    private var isFiltering: Bool {
        settings.downloadsFilter != .all
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

    /// Episodes from the **full completed Downloads catalog** (`DownloadService.downloads`,
    /// catalog/persist order — oldest completed first) that are not already queued — same catalog
    /// as Delete played downloads / tab badge, **not** the chip/search filtered list.
    /// Confirm count and `enqueueAllDownloads()` share this eligibility.
    private var enqueueAllDownloadsCandidatesCount: Int {
        downloads.downloads.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide). Distinct from tab badge (full catalog count).
    private var downloadsRemainingInfoLabel: String? {
        guard !filteredDownloads.isEmpty else { return nil }
        let summary = downloadsRemainingSummary
        let episodesWord: String
        if summary.episodeCount == 1 {
            episodesWord = String(localized: "1 episode")
        } else {
            episodesWord = String(localized: "\(summary.episodeCount) episodes")
        }
        // All durations unknown — show count only (no invented time).
        guard summary.knownCount > 0 else {
            return episodesWord
        }
        let formatted = StatisticsView.formatDuration(summary.remainingSeconds)
        let timePart: String
        if summary.unknownCount > 0 {
            timePart = String(localized: "~\(formatted)")
        } else {
            timePart = formatted
        }
        return String(localized: "\(episodesWord) • \(timePart) left")
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

    private var downloadsRemainingSummary: DownloadsRemainingSummary {
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for item in filteredDownloads {
            let episode = item.episode
            guard let duration = knownDurationSeconds(for: episode) else {
                unknown += 1
                continue
            }
            known += 1
            // Mark-played clears position; do not count full duration as still left
            // (unless this is the live current episode — use live position instead).
            if store.isPlayed(episode.id), playback.currentEpisode?.id != episode.id {
                continue
            }
            let position = positionSeconds(for: episode)
            remaining += max(0, duration - position)
        }
        return DownloadsRemainingSummary(
            episodeCount: filteredDownloads.count,
            remainingSeconds: remaining,
            knownCount: known,
            unknownCount: unknown
        )
    }

    /// Prefer live player duration when this episode is current; else feed `itunes:duration` /
    /// media; else saved playback duration. Never invents a length.
    private func knownDurationSeconds(for episode: PodcastEpisode) -> Double? {
        if playback.currentEpisode?.id == episode.id {
            let live = playback.durationSeconds
            if live.isFinite, live > 0 { return live }
        }
        if episode.hasKnownDuration {
            return episode.durationSeconds
        }
        let saved = store.playbackState(for: episode.id).durationSeconds
        if saved.isFinite, saved > 0 { return saved }
        return nil
    }

    /// Live player position when current; else saved progress (`0` when unplayed / cleared).
    private func positionSeconds(for episode: PodcastEpisode) -> Double {
        if playback.currentEpisode?.id == episode.id {
            let live = playback.positionSeconds
            return live.isFinite ? max(0, live) : 0
        }
        return max(0, store.positionSeconds(for: episode.id))
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
                                    selected: settings.downloadsFilter == chip
                                ) {
                                    settings.downloadsFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                    .accessibilityLabel("Sort downloads")
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
                    .accessibilityLabel("Download errors")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllDownloadsCandidatesCount == 0)
                        .accessibilityHint("Appends downloaded episodes not already queued")

                        Button(role: .destructive) {
                            showDeletePlayedConfirm = true
                        } label: {
                            Label("Delete played downloads", systemImage: "trash")
                        }
                        .disabled(playedDownloadsForDelete.isEmpty)
                    } label: {
                        Label("Downloads actions", systemImage: "ellipsis.circle")
                    }
                    // Menu available whenever the completed catalog is non-empty (Add all / Delete played
                    // each disable independently — same honesty as Favorites Add all + Clear).
                    .disabled(downloads.downloads.isEmpty)
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


/// Sum of remaining seconds over the visible Downloads list (filtered).
private struct DownloadsRemainingSummary {
    var episodeCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}

private struct DownloadsFilterChip: View {
    let title: String
    let selected: Bool
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
        .accessibilityHint(String(localized: "Filters the Downloads list"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Simple list of persisted download failures (ring buffer) with clear action.
struct DownloadErrorsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            if downloads.recentErrors.isEmpty {
                ContentUnavailableView(
                    "No download errors",
                    systemImage: "checkmark.circle",
                    description: Text("Failed downloads will appear here (up to \(DownloadService.downloadErrorRingCapacity) recent).")
                )
            } else {
                ForEach(downloads.recentErrors) { entry in
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
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Download errors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(downloads.recentErrors.isEmpty && downloads.lastError == nil)
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
}
