import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.editMode) private var editMode

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearQueueConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Chip ≠ All or non-empty search — Edit/`.onMove` disabled (filtered IndexSet ≠ full queue).
    /// EpisodeRow Move to top/bottom still uses episode id → full-queue indices (safe while filtering).
    private var isFiltering: Bool {
        settings.queueFilter != .all
            || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drag / Edit reorder allowed only when unlocked and not filtering.
    private var canReorder: Bool {
        !settings.queueLocked && !isFiltering
    }

    /// Visible queue rows: chip (`isPlayed`) → search. Empty query shows the chip-filtered queue order.
    /// Clear queue / Play Next stay full-queue scoped (not the visible subset).
    private var filteredQueue: [PodcastEpisode] {
        var base = store.queue
        switch settings.queueFilter {
        case .all:
            break
        case .unplayed:
            base = base.filter { !store.isPlayed($0.id) }
        case .played:
            base = base.filter { store.isPlayed($0.id) }
        }
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { episode in
            if episode.title.localizedCaseInsensitiveContains(q) { return true }
            let feedTitle = store.feed(containingEpisodeId: episode.id)?.title ?? ""
            return feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide).
    private var queueRemainingInfoLabel: String? {
        guard !filteredQueue.isEmpty else { return nil }
        let summary = queueRemainingSummary
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

    private var queueRemainingAccessibilityLabel: String {
        guard let label = queueRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Queue remaining time \(label)")]
        let unknown = queueRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var queueRemainingSummary: QueueRemainingSummary {
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for episode in filteredQueue {
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
        return QueueRemainingSummary(
            episodeCount: filteredQueue.count,
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
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QueueFilter.allCases) { chip in
                                QueueFilterChip(
                                    title: chip.label,
                                    selected: settings.queueFilter == chip
                                ) {
                                    settings.queueFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // AntennaPod-like queue info bar (visible filtered list remaining time).
                if let remainingLabel = queueRemainingInfoLabel {
                    Section {
                        Text(remainingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(queueRemainingAccessibilityLabel)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }

                if store.queue.isEmpty {
                    ContentUnavailableView(
                        "Queue empty",
                        systemImage: "list.bullet",
                        description: Text(
                            settings.queueLocked
                                ? String(localized: "Add episodes from a podcast feed. Queue is locked — unlock to drag reorder.")
                                : String(localized: "Add episodes from a podcast feed. Edit mode lets you drag to reorder.")
                        )
                    )
                } else if filteredQueue.isEmpty {
                    ContentUnavailableView(
                        "No matching queue episodes",
                        systemImage: "magnifyingglass",
                        description: Text(
                            isFiltering
                                ? String(localized: "No queue episodes match your filter.")
                                : String(localized: "No queue episodes match your search.")
                        )
                    )
                } else {
                    ForEach(filteredQueue) { episode in
                        EpisodeRow(
                            episode: episode,
                            feedTitle: store.feed(containingEpisodeId: episode.id)?.title ?? ""
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.removeFromQueue(episode)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.archive(episode.id)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove(perform: canReorder ? { source, destination in
                        // Indices are only valid when the list shows the full queue (All + empty search).
                        store.moveQueue(from: source, to: destination)
                    } : nil)
                }
            }
            .navigationTitle("Queue")
            .searchable(text: $searchText, prompt: "Search queue")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onChange(of: isFiltering) { _, filtering in
                // Drag reorder uses full-queue indices; leave Edit while a chip/search filter is active.
                if filtering {
                    editMode?.wrappedValue = .inactive
                }
            }
            .onChange(of: settings.queueLocked) { _, locked in
                // Leave Edit when locking so drag handles disappear immediately.
                if locked {
                    editMode?.wrappedValue = .inactive
                }
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        settings.queueLocked.toggle()
                    } label: {
                        Label(
                            settings.queueLocked
                                ? String(localized: "Unlock queue")
                                : String(localized: "Lock queue"),
                            systemImage: settings.queueLocked ? "lock.fill" : "lock.open"
                        )
                    }
                    .accessibilityLabel(
                        settings.queueLocked
                            ? String(localized: "Unlock queue")
                            : String(localized: "Lock queue")
                    )
                    .accessibilityHint(
                        settings.queueLocked
                            ? String(localized: "Allows drag reorder and Move to top or bottom")
                            : String(localized: "Disables drag reorder and Move to top or bottom")
                    )
                    .accessibilityAddTraits(.isButton)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        // Hide reorder while filtering or locked — filtered IndexSet ≠ full queue; lock = no manual reorder.
                        .disabled(store.queue.isEmpty || !canReorder)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            // Always confirm before clearQueue() — never clear from the menu alone.
                            showClearQueueConfirm = true
                        } label: {
                            Label("Clear queue", systemImage: "trash")
                        }
                        // Clear always targets the full queue (not the filtered subset).
                        // Queue lock does **not** disable Clear — reorder-only lock (Android parity).
                        .disabled(store.queue.isEmpty)
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then removes every episode from the queue")
                        )
                    } label: {
                        Label("Queue actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(store.queue.isEmpty)
                    .accessibilityLabel(String(localized: "Queue actions"))
                    .accessibilityHint(
                        String(localized: "Clear the entire queue after confirmation")
                    )
                }
            }
            .confirmationDialog(
                "Clear queue?",
                isPresented: $showClearQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear queue", role: .destructive) {
                    store.clearQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(store.queue.count) episodes from the entire queue (not only the current filter). Does not stop playback, change progress, mark played, or delete downloads."
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

/// Sum of remaining seconds over the visible Queue list (filtered).
private struct QueueRemainingSummary {
    var episodeCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}

/// Filter chip for Queue All / Unplayed / Played (mirrors Downloads / Feed detail).
private struct QueueFilterChip: View {
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
        .accessibilityHint(String(localized: "Filters the Queue list"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
