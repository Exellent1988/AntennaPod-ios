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
    @State private var showShuffleQueueConfirm = false
    @State private var showShuffleKeepPlayingFirstConfirm = false
    @State private var showReverseQueueConfirm = false
    @State private var showSortNewestQueueConfirm = false
    @State private var showSortOldestQueueConfirm = false
    @State private var showSortShortestQueueConfirm = false
    @State private var showSortLongestQueueConfirm = false
    /// Single episode pending swipe-remove confirmation (nil = dialog dismissed).
    @State private var episodePendingRemove: PodcastEpisode?

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

    /// Shuffle always targets the **full** persisted queue (not chip/search). Allowed when unlocked
    /// and at least two items — filter state does not matter (unlike Edit/`onMove` index mapping).
    private var canShuffle: Bool {
        !settings.queueLocked && store.queue.count >= 2
    }

    /// Reverse order always targets the **full** persisted queue (not chip/search). Same gate as Shuffle:
    /// unlocked and at least two items — filter state does not matter.
    private var canReverse: Bool {
        !settings.queueLocked && store.queue.count >= 2
    }

    /// Sort by publish date always targets the **full** persisted queue (not chip/search). Same gate as
    /// Shuffle/Reverse: unlocked and at least two items — filter state does not matter.
    private var canSortByDate: Bool {
        !settings.queueLocked && store.queue.count >= 2
    }

    /// Sort by duration always targets the **full** persisted queue (not chip/search). Same gate as
    /// Shuffle/Reverse/Sort by date: unlocked and at least two items — filter state does not matter.
    private var canSortByDuration: Bool {
        !settings.queueLocked && store.queue.count >= 2
    }

    /// Move the **currently playing** episode to queue index 0 (`moveQueueItemToTop`).
    /// Enabled when unlocked, current episode is in the queue, and not already first.
    /// Distinct from per-row EpisodeRow Move to top — this is a toolbar shortcut for *playing*.
    private var canMovePlayingToTop: Bool {
        guard !settings.queueLocked,
              let current = playback.currentEpisode,
              let index = store.queue.firstIndex(where: { $0.id == current.id }) else {
            return false
        }
        return index > 0
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
                                // Same path as Full Player Remove from queue — confirm first.
                                episodePendingRemove = episode
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .accessibilityHint(
                                String(localized: "Asks for confirmation, then removes this episode from the queue")
                            )
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
                            ? String(localized: "Allows drag reorder, Shuffle, Shuffle keep playing first, Reverse order, Sort by date, Sort by duration, Move playing to top, and Move to top or bottom")
                            : String(localized: "Disables drag reorder, Shuffle, Shuffle keep playing first, Reverse order, Sort by date, Sort by duration, Move playing to top, and Move to top or bottom")
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
                        Button {
                            // Always confirm before shuffleQueue() — reorders the full list.
                            showShuffleQueueConfirm = true
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                        // Shuffle always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canShuffle)
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then randomly reorders the entire queue")
                        )
                        Button {
                            // Always confirm before shuffleQueueKeepingPlayingFirst — full-list shuffle + pin playing.
                            showShuffleKeepPlayingFirstConfirm = true
                        } label: {
                            Label("Shuffle (keep playing first)", systemImage: "shuffle")
                        }
                        // Same gates as plain Shuffle: full queue, locked blocks, count < 2 disabled.
                        // Reuses shuffleQueue + moveQueueItemToTop; if nothing playing / not queued → plain shuffle.
                        .disabled(!canShuffle)
                        .accessibilityLabel(String(localized: "Shuffle keep playing first"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then shuffles the entire queue and keeps the currently playing episode first when it is in the queue")
                        )
                        Button {
                            // Always confirm before reverseQueue() — reorders the full list.
                            showReverseQueueConfirm = true
                        } label: {
                            Label("Reverse order", systemImage: "arrow.up.arrow.down")
                        }
                        // Reverse always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canReverse)
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then reverses the entire queue order")
                        )
                        Button {
                            // Always confirm before sortQueueByPublishDate — reorders the full list.
                            showSortNewestQueueConfirm = true
                        } label: {
                            Label("Newest first", systemImage: "calendar")
                        }
                        // Sort always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canSortByDate)
                        .accessibilityLabel(String(localized: "Sort newest first"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then sorts the entire queue by publish date, newest first")
                        )
                        Button {
                            // Always confirm before sortQueueByPublishDate — reorders the full list.
                            showSortOldestQueueConfirm = true
                        } label: {
                            Label("Oldest first", systemImage: "calendar")
                        }
                        // Sort always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canSortByDate)
                        .accessibilityLabel(String(localized: "Sort oldest first"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then sorts the entire queue by publish date, oldest first")
                        )
                        Button {
                            // Always confirm before sortQueueByDuration — reorders the full list.
                            showSortShortestQueueConfirm = true
                        } label: {
                            Label("Shortest first", systemImage: "timer")
                        }
                        // Sort always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canSortByDuration)
                        .accessibilityLabel(String(localized: "Sort shortest first"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then sorts the entire queue by known duration, shortest first")
                        )
                        Button {
                            // Always confirm before sortQueueByDuration — reorders the full list.
                            showSortLongestQueueConfirm = true
                        } label: {
                            Label("Longest first", systemImage: "timer")
                        }
                        // Sort always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canSortByDuration)
                        .accessibilityLabel(String(localized: "Sort longest first"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then sorts the entire queue by known duration, longest first")
                        )
                        Button {
                            // Reuse moveQueueItemToTop — no seek/stop; no confirm (single-item reorder).
                            if let current = playback.currentEpisode {
                                store.moveQueueItemToTop(current)
                            }
                        } label: {
                            Label("Move playing to top", systemImage: "arrow.up.to.line")
                        }
                        // Enabled only when current episode is queued and not already first;
                        // blocked when Queue locked (reorder-only, same as Shuffle/Reverse/Sort/Move to top).
                        .disabled(!canMovePlayingToTop)
                        .accessibilityLabel(String(localized: "Move playing to top"))
                        .accessibilityHint(
                            String(localized: "Moves the currently playing episode to the start of the queue")
                        )
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
                        String(localized: "Shuffle, shuffle keep playing first, reverse, sort by date, sort by duration, move playing to top, or clear the entire queue")
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
            .confirmationDialog(
                "Shuffle queue?",
                isPresented: $showShuffleQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Shuffle") {
                    store.shuffleQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Randomly reorders all \(store.queue.count) episodes in the entire queue (not only the current filter). Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Shuffle queue (keep playing first)?",
                isPresented: $showShuffleKeepPlayingFirstConfirm,
                titleVisibility: .visible
            ) {
                Button("Shuffle (keep playing first)") {
                    store.shuffleQueueKeepingPlayingFirst(currentEpisode: playback.currentEpisode)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Randomly reorders all \(store.queue.count) episodes in the entire queue (not only the current filter), then moves the currently playing episode to the start when it is in the queue. If nothing is playing or the current episode is not queued, behaves like Shuffle. Does not stop playback, change progress, mark played, or delete downloads."
                )
            }
            .confirmationDialog(
                "Reverse queue?",
                isPresented: $showReverseQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Reverse order") {
                    store.reverseQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Reverses all \(store.queue.count) episodes in the entire queue (not only the current filter). Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Sort queue newest first?",
                isPresented: $showSortNewestQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Newest first") {
                    store.sortQueueByPublishDate(newestFirst: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Sorts all \(store.queue.count) episodes in the entire queue by publish date, newest first (not only the current filter). Episodes without a date go last. Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Sort queue oldest first?",
                isPresented: $showSortOldestQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Oldest first") {
                    store.sortQueueByPublishDate(newestFirst: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Sorts all \(store.queue.count) episodes in the entire queue by publish date, oldest first (not only the current filter). Episodes without a date go last. Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Sort queue shortest first?",
                isPresented: $showSortShortestQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Shortest first") {
                    store.sortQueueByDuration(shortestFirst: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Sorts all \(store.queue.count) episodes in the entire queue by known duration, shortest first (not only the current filter). Duration from feed or saved playback when known; episodes with unknown duration go last. Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Sort queue longest first?",
                isPresented: $showSortLongestQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Longest first") {
                    store.sortQueueByDuration(shortestFirst: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Sorts all \(store.queue.count) episodes in the entire queue by known duration, longest first (not only the current filter). Duration from feed or saved playback when known; episodes with unknown duration go last. Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Remove from queue?",
                isPresented: Binding(
                    get: { episodePendingRemove != nil },
                    set: { if !$0 { episodePendingRemove = nil } }
                ),
                titleVisibility: .visible,
                presenting: episodePendingRemove
            ) { episode in
                Button("Remove from queue", role: .destructive) {
                    store.removeFromQueue(episode)
                    episodePendingRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    episodePendingRemove = nil
                }
            } message: { episode in
                Text(
                    "Remove \"\(episode.title)\" from the queue? Removes from the queue only. Does not delete the download, mark played, or stop playback."
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
