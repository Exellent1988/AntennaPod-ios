import SwiftUI

struct ArchivedView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showRestoreAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full archived catalog (store order: newest archived first) — Restore all always uses this count.
    private var items: [ArchivedEpisode] {
        store.archivedEpisodes
    }

    /// Visible archived ordered by `AppSettings.archivedSort`.
    /// Sort key: `ArchivedEpisode.archivedAtEpochMs` (`archivedAtById` / `archived.json`).
    /// Empty query shows the full list; sort applies to search-filtered results too.
    /// Does not mutate `PodcastStore.archivedEpisodes` (Restore all counts stay on newest-first catalog).
    private var filteredItems: [ArchivedEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        let filtered: [ArchivedEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
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
            }
        }
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Archived list
    /// (sort + searchable filter). **Honesty:** archived ≠ played — use normal duration−position
    /// rules (not “archived means finished”). Remaining per episode = `max(0, duration − position)`
    /// when duration known; unplayed with duration contributes full duration; **played** (not
    /// current) → 0; **unknown duration skipped** (tilde when any skipped). Currently playing uses
    /// live `PlaybackService` position/duration. Wall-clock only (no playback-speed divide).
    /// Distinct from Restore all count (always full catalog).
    private var archivedRemainingInfoLabel: String? {
        guard !filteredItems.isEmpty else { return nil }
        let summary = archivedRemainingSummary
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

    private var archivedRemainingAccessibilityLabel: String {
        guard let label = archivedRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Archived remaining time \(label)")]
        let unknown = archivedRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var archivedRemainingSummary: ArchivedRemainingSummary {
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for item in filteredItems {
            let episode = item.episode
            guard let duration = knownDurationSeconds(for: episode) else {
                unknown += 1
                continue
            }
            known += 1
            // Mark-played clears position; do not count full duration as still left
            // (unless this is the live current episode — use live position instead).
            // Archived honesty: archived ≠ played; only `isPlayed` (not current) → 0.
            if store.isPlayed(episode.id), playback.currentEpisode?.id != episode.id {
                continue
            }
            let position = positionSeconds(for: episode)
            remaining += max(0, duration - position)
        }
        return ArchivedRemainingSummary(
            episodeCount: filteredItems.count,
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
        List {
            // AntennaPod-like archived info bar (visible sorted+filtered list remaining time).
            // Hidden when catalog empty or search matches nothing — not full-catalog Restore all count.
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
                    description: Text("No archived episodes match your search.")
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
                .accessibilityLabel("Sort archived")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
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

/// Sum of remaining seconds over the visible Archived list (sort + searchable filter).
private struct ArchivedRemainingSummary {
    var episodeCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}
