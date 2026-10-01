import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearHistoryConfirm = false
    @State private var showEnqueueAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full history catalog (store order: newest last-played first) — Clear history always uses this count.
    private var items: [HistoryEpisode] {
        store.historyEpisodes
    }

    /// Episodes from the **full History catalog** (`store.historyEpisodes`, newest last-played first) that are
    /// not already queued — same catalog as Clear history, **not** the searchable filtered list.
    /// Confirm count and `enqueueAllHistory()` share this eligibility.
    private var enqueueAllHistoryCandidatesCount: Int {
        items.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Visible history ordered by `AppSettings.historySort`.
    /// Sort key: `HistoryEpisode.lastPlayedAtEpochMs` (`lastPlayedAt`, else `updatedAt` from playback state).
    /// Empty query shows the full list; sort applies to search-filtered results too.
    /// Does not mutate `PodcastStore.historyEpisodes` (Home Continue / Clear history stay newest-first catalog).
    /// Respects history size limit catalog as-is (store already trimmed).
    private var filteredItems: [HistoryEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        let filtered: [HistoryEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
                return item.feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.historySort {
            case .newestFirst:
                if lhs.lastPlayedAtEpochMs != rhs.lastPlayedAtEpochMs {
                    return lhs.lastPlayedAtEpochMs > rhs.lastPlayedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.lastPlayedAtEpochMs != rhs.lastPlayedAtEpochMs {
                    return lhs.lastPlayedAtEpochMs < rhs.lastPlayedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            }
        }
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** History list
    /// (sort + searchable filter). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0 (History is mostly played / in-progress — low totals are expected and correct; still
    /// useful for in-progress); **unknown duration skipped** (tilde when any skipped). Currently
    /// playing uses live `PlaybackService` position/duration. Wall-clock only (no playback-speed
    /// divide). Distinct from Clear history count (always full catalog). Respects history size
    /// limit catalog as-is — never invents beyond the store-trimmed set.
    private var historyRemainingInfoLabel: String? {
        guard !filteredItems.isEmpty else { return nil }
        let summary = historyRemainingSummary
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

    private var historyRemainingAccessibilityLabel: String {
        guard let label = historyRemainingInfoLabel else { return "" }
        var parts = [String(localized: "History remaining time \(label)")]
        let unknown = historyRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var historyRemainingSummary: HistoryRemainingSummary {
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
            // History honesty: played (not current) → 0 remaining is correct.
            if store.isPlayed(episode.id), playback.currentEpisode?.id != episode.id {
                continue
            }
            let position = positionSeconds(for: episode)
            remaining += max(0, duration - position)
        }
        return HistoryRemainingSummary(
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
            // AntennaPod-like history info bar (visible sorted+filtered list remaining time).
            // Hidden when catalog empty or search matches nothing — not full-catalog Clear count.
            // Played (not current) → 0; totals may often be low — still useful for in-progress.
            if let remainingLabel = historyRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(historyRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Episodes you play or mark as played appear here, ordered by last played.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching history",
                    systemImage: "magnifyingglass",
                    description: Text("No history matches your search.")
                )
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Last played")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.removeFromHistory(item.episode.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if store.isPlayed(item.episode.id) {
                            Button {
                                store.markUnplayed(item.episode.id)
                            } label: {
                                Label("Mark unplayed", systemImage: "circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
                if let limit = settings.historySizeLimit.entryLimit {
                    Section {
                        Text(
                            String(
                                localized: "History is capped at \(limit) episodes (Settings → Library → History size). Oldest last-played entries are removed first."
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(
                                localized: "History is capped at \(limit) episodes (Settings → Library → History size). Oldest last-played entries are removed first."
                            )
                        )
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search history")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.historySort) {
                        ForEach(HistorySort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort history"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllHistoryCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Appends history episodes not already queued"))

                    Button(role: .destructive) {
                        showClearHistoryConfirm = true
                    } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                    // Clear always targets the full history list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("History actions", systemImage: "ellipsis.circle")
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
                store.enqueueAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllHistoryCandidatesCount) history episodes to the end of the queue (newest last-played first). Already queued episodes are skipped. Uses the full History catalog (same as Clear history), not the searchable filter. Queue lock does not block enqueue.")
        }
        .confirmationDialog(
            "Clear history?",
            isPresented: $showClearHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                store.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(items.count) episodes from history. Does not unsubscribe, delete downloads, or clear the queue.")
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

/// Sum of remaining seconds over the visible History list (sort + searchable filter).
private struct HistoryRemainingSummary {
    var episodeCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}
