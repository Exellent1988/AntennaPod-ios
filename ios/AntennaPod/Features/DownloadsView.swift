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
                                VStack(alignment: .leading) {
                                    Text(item.episode.title)
                                        .font(.headline)
                                    Text(item.localFileURL.lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    playback.play(episode: item.episode)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.bordered)
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
                                    downloads.delete(item.episode)
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
                        Button(role: .destructive) {
                            showDeletePlayedConfirm = true
                        } label: {
                            Label("Delete played downloads", systemImage: "trash")
                        }
                        .disabled(playedDownloadsForDelete.isEmpty)
                    } label: {
                        Label("Downloads actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(playedDownloadsForDelete.isEmpty)
                }
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
