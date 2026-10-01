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

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide). Distinct from tab badge (full catalog count).
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
            savedPositionSeconds: { store.positionSeconds(for: $0) }
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
                    .accessibilityLabel(String(localized: "Sort downloads"))
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
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllDownloadsCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends downloaded episodes not already queued"))

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
                    // Menu available whenever the completed catalog is non-empty (Add all / Delete played /
                    // Clear all each disable independently — same honesty as Favorites Add all + Clear).
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
