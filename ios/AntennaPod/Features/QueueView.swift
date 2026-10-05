import SwiftUI
import UIKit

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
    @State private var showRemovePlayedConfirm = false
    @State private var showMarkAllQueuePlayedConfirm = false
    @State private var showMarkAllQueueUnplayedConfirm = false
    @State private var showArchiveAllQueueConfirm = false
    @State private var showShuffleQueueConfirm = false
    @State private var showShuffleKeepPlayingFirstConfirm = false
    @State private var showReverseQueueConfirm = false
    @State private var showSortNewestQueueConfirm = false
    @State private var showSortOldestQueueConfirm = false
    @State private var showSortShortestQueueConfirm = false
    @State private var showSortLongestQueueConfirm = false
    @State private var showSortTitleAZQueueConfirm = false
    @State private var showSortTitleZAQueueConfirm = false
    /// Single episode pending swipe-remove confirmation (nil = dialog dismissed).
    @State private var episodePendingRemove: PodcastEpisode?
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Chip ≠ All, podcast ≠ All, or non-empty search — Edit/`.onMove` disabled (filtered IndexSet ≠ full queue).
    /// EpisodeRow Move to top/bottom still uses episode id → full-queue indices (safe while filtering).
    private var isFiltering: Bool {
        settings.queueFilter != .all
            || isPodcastFiltering
            || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Played-status or podcast chip only. Search is not a chip: the empty copy must
    /// not call a search miss a filter miss (`isFiltering` includes the query).
    private var hasQueueChipOrPodcastFilter: Bool {
        settings.queueFilter != .all || isPodcastFiltering
    }

    /// Visible empty copy when the persisted queue is non-empty but no row matches.
    /// Chip or podcast filter wins when one is set; otherwise this is a search miss.
    private var queueNoMatchMessage: String {
        if hasQueueChipOrPodcastFilter {
            return String(localized: "No queue episodes match your filter.")
        }
        return String(localized: "No queue episodes match your search.")
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

    /// Sort by title always targets the **full** persisted queue (not chip/search). Same gate as
    /// Shuffle/Reverse/Sort by date/duration: unlocked and at least two items — filter state does not matter.
    private var canSortByTitle: Bool {
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

    /// Move the **currently playing** episode to the end of the queue (`moveQueueItemToBottom`).
    /// Enabled when unlocked, current episode is in the queue, and not already last.
    /// Mirror of `canMovePlayingToTop` — same reorder-only gate; no confirm (single-item reorder).
    private var canMovePlayingToBottom: Bool {
        guard !settings.queueLocked,
              let current = playback.currentEpisode,
              let index = store.queue.firstIndex(where: { $0.id == current.id }) else {
            return false
        }
        return index < store.queue.count - 1
    }

    /// Count of **played** episodes in the **full** persisted queue (`isPlayed`) — not chip/search.
    /// Used for Remove played enablement + confirmation count (same honesty as Clear queue).
    private var playedInFullQueueCount: Int {
        store.queue.filter { store.isPlayed($0.id) }.count
    }

    /// Remove played targets the **full** persisted queue. Enabled when at least one played item
    /// is queued. Queue lock does **not** disable (reorder-only, same as Clear queue).
    private var canRemovePlayed: Bool {
        playedInFullQueueCount > 0
    }

    /// Count of unplayed, non-archived episodes in the **full** persisted queue — not chip/search.
    /// Mark all as played uses the same archive policy as sibling bulk actions.
    private var markAllQueuePlayedCandidatesCount: Int {
        store.markAllQueuePlayedCandidateCount()
    }

    /// Count of played episodes in the full persisted queue, including archived episodes.
    /// Mark all as unplayed uses the same full-catalog policy as sibling bulk actions.
    private var markAllQueueUnplayedCandidatesCount: Int {
        store.markAllQueueUnplayedCandidateCount()
    }

    /// Count of non-archived episodes in the full persisted queue — not chip, podcast, or search filtered.
    private var archiveAllQueueCandidatesCount: Int {
        store.archiveAllQueueCandidateCount()
    }

    /// Queued episodes with playable media via shared `EpisodePlayRandom` (local file via
    /// `DownloadService.localURL` — downloads + local-folder `file://` — or streamable http(s)
    /// `downloadUrl`). Full persisted queue — **not** played-chip / podcast-chip / searchable filtered.
    /// Distinct from Shuffle (reorder) / Clear / Remove played / remaining-time visible counts.
    /// Queue lock does **not** gate Play random (not a reorder).
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: store.queue,
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible queued episode is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: QueuePodcastFilter {
        QueuePodcastFilter.fromStorage(settings.queuePodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one queued episode.
    /// Built from the persisted queue via `feed(containingEpisodeId:)` — never invent.
    /// Order matches the chip label: display title (custom title when set, else RSS title).
    private var queuePodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        let feedsByEpisodeId = queueFeedsByEpisodeId()
        for episode in store.queue {
            guard let feed = queueFeed(for: episode.id, in: feedsByEpisodeId) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return queuePodcastsByDisplayTitle(feeds)
    }

    /// Episode id → first feed whose `episodes` holds it, for queued ids only (same answer as
    /// `PodcastStore.feed(containingEpisodeId:)`). One pass over the library; calling the store
    /// per queue row scanned every feed's episodes once per row, on every 0.5s playback tick.
    private func queueFeedsByEpisodeId() -> [String: PodcastFeed] {
        let queueIds = Set(store.queue.map(\.id))
        var result: [String: PodcastFeed] = [:]
        guard !queueIds.isEmpty else { return result }
        for feed in store.feeds {
            for episode in feed.episodes where queueIds.contains(episode.id) && result[episode.id] == nil {
                result[episode.id] = feed
            }
        }
        return result
    }

    /// Map hit, else the store's synthetic `podcast-trailer:` id fallback (trailers are not in
    /// `feed.episodes`). Any other miss is nil in the store too.
    private func queueFeed(for episodeId: String, in feedsByEpisodeId: [String: PodcastFeed]) -> PodcastFeed? {
        if let feed = feedsByEpisodeId[episodeId] {
            return feed
        }
        guard episodeId.hasPrefix("podcast-trailer:") else { return nil }
        return store.feed(containingEpisodeId: episodeId)
    }

    /// A–Z by the name the chip shows. Raw RSS title would place a renamed podcast
    /// where the old name sorts, so the visible label and the row disagree.
    private func queuePodcastsByDisplayTitle(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        feeds.sorted {
            store.displayTitle(for: $0).localizedCaseInsensitiveCompare(
                store.displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    private var podcastFilterChips: [QueuePodcastFilter] {
        var chips: [QueuePodcastFilter] = [.all]
        var feeds = queuePodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has queue items)
        // so the user can see why the list is empty and tap All.
        if case .feed(let id) = podcastFilter,
           !feeds.contains(where: { $0.id == id }),
           let feed = store.feeds.first(where: { $0.id == id }) {
            feeds.append(feed)
            feeds = queuePodcastsByDisplayTitle(feeds)
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later queue row looks filtered out.
    private func releaseQueuePodcastFilterIfFeedGone() {
        guard case .feed(let id) = QueuePodcastFilter.fromStorage(settings.queuePodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.queuePodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: QueuePodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.nonEmptyDisplayTitle(forFeedId: id)
                ?? queuePodcastFeeds.first(where: { $0.id == id }).flatMap { store.nonEmptyDisplayTitle(for: $0) }
                ?? String(localized: "Unknown podcast")
        }
    }

    /// Visible queue rows: played chip (`isPlayed`) → podcast chip → search.
    /// Empty query shows the chip+podcast-filtered queue order (persisted order preserved).
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail), plus
    /// feed display title. View-only — does not remove episodes from the actual queue.
    /// Clear queue / Remove played / Shuffle / Play random / lock ops / Play Next stay full-queue scoped (not the visible subset).
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
        // Built only when the podcast chip or search needs each row's podcast.
        var feedsByEpisodeId: [String: PodcastFeed] = [:]
        if podcastFilter != .all || !q.isEmpty {
            feedsByEpisodeId = queueFeedsByEpisodeId()
        }
        switch podcastFilter {
        case .all:
            break
        case .feed(let feedId):
            base = base.filter { queueFeed(for: $0.id, in: feedsByEpisodeId)?.id == feedId }
        }
        if q.isEmpty { return base }
        return base.filter { episode in
            if store.episodeMatchesLibraryQuery(episode, query: q) { return true }
            let feedTitle = queueFeed(for: episode.id, in: feedsByEpisodeId)
                .map { store.displayTitle(for: $0) } ?? ""
            return feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// Distinct from Clear queue / Remove played / Shuffle / Play random eligibility (always full queue).
    private var queueRemainingInfoLabel: String? {
        guard !filteredQueue.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: queueRemainingSummary)
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

    /// VoiceOver hint for the Queue remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and what the bar is not.
    private var queueRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Queue bar is the visible list after the played-status chip, podcast filter, and search. Reorder and sort change order only. Played episodes that are not currently playing count as zero. It is not the full queue behind Clear queue, Remove played, Shuffle, Play random, Mark all as played, Mark all as unplayed, Archive all, Copy queue, or Share queue, and not the Home Queue preview or the All Episodes newest-500 cap. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. Queue lock does not change this total. This is not the mini player or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Queue bar is the visible list after the played-status chip, podcast filter, and search. Reorder and sort change order only. Played episodes that are not currently playing count as zero. It is not the full queue behind Clear queue, Remove played, Shuffle, Play random, Mark all as played, Mark all as unplayed, Archive all, Copy queue, or Share queue, and not the Home Queue preview or the All Episodes newest-500 cap. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. Queue lock does not change this total. This is not the mini player or Lock Screen. It does not play, download, or mark episodes played.")
    }

    /// VoiceOver value for the two queue empty states. Keep the full-catalog empty
    /// state distinct from a view-only chip/search mismatch, including Queue lock guidance.
    private var queueEmptyStateAccessibilityValue: String {
        if store.queue.isEmpty {
            return settings.queueLocked
                ? String(localized: "Add episodes from a podcast feed. Queue is locked — unlock to drag reorder.")
                : String(localized: "Add episodes from a podcast feed. Edit mode lets you drag to reorder.")
        }
        return queueNoMatchMessage
    }

    private var queueRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredQueue,
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

    /// Plain-text list of the **full** persisted queue — not chip/podcast/search filtered.
    /// Same honesty as Clear queue / Remove played / Shuffle (full `store.queue`).
    private var queuePlainText: String {
        QueueExport.plainText(episodes: store.queue) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the full queue is non-empty. Queue lock does **not** disable (read-only export).
    private var canExportQueue: Bool {
        !store.queue.isEmpty
    }

    /// “Queue” header + body for system share sheet (same body as Copy).
    private var queueShareText: String {
        QueueExport.shareText(episodes: store.queue) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
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
                                    selected: settings.queueFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Queue list")
                                ) {
                                    settings.queueFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if !store.queue.isEmpty, !queuePodcastFeeds.isEmpty || isPodcastFiltering {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(podcastFilterChips) { chip in
                                    QueueFilterChip(
                                        title: podcastChipTitle(chip),
                                        selected: podcastFilter == chip,
                                        accessibilityHint: String(localized: "Filters the Queue list by podcast")
                                    ) {
                                        settings.queuePodcastFilter = chip.storageValue
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
                            .accessibilityHint(queueRemainingAccessibilityHint)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Queue empty"))
                    .accessibilityValue(queueEmptyStateAccessibilityValue)
                } else if filteredQueue.isEmpty {
                    ContentUnavailableView(
                        "No matching queue episodes",
                        systemImage: "magnifyingglass",
                        description: Text(queueNoMatchMessage)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "No matching queue episodes"))
                    .accessibilityValue(queueEmptyStateAccessibilityValue)
                } else {
                    ForEach(filteredQueue) { episode in
                        EpisodeRow(
                            episode: episode,
                            feedTitle: store.displayTitle(containingEpisodeId: episode.id)
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
                                store.togglePlayed(episode.id)
                            } label: {
                                Label(
                                    store.isPlayed(episode.id)
                                        ? String(localized: "Mark unplayed")
                                        : String(localized: "Mark played"),
                                    systemImage: store.isPlayed(episode.id) ? "circle" : "checkmark.circle"
                                )
                            }
                            .tint(.blue)
                            .accessibilityHint(
                                store.isPlayed(episode.id)
                                    ? String(localized: "Marks this episode as unplayed")
                                    : String(localized: "Marks this episode as played")
                            )
                            Button {
                                // Archived episodes stay in the queue, so this swipe must undo
                                // as well as archive — same toggle as the row button. A one-way
                                // archive() leaves the action labeled Archive and does nothing.
                                store.toggleArchived(episode.id)
                            } label: {
                                Label(
                                    store.isArchived(episode.id)
                                        ? String(localized: "Restore")
                                        : String(localized: "Archive"),
                                    systemImage: store.isArchived(episode.id)
                                        ? "arrow.uturn.backward"
                                        : "archivebox"
                                )
                            }
                            .tint(store.isArchived(episode.id) ? .green : .orange)
                            .accessibilityHint(
                                store.isArchived(episode.id)
                                    ? String(localized: "Restores this episode from the archive")
                                    : String(localized: "Hides this episode from Inbox without marking it played")
                            )
                        }
                    }
                    .onMove(perform: canReorder ? { source, destination in
                        // Indices are only valid when the list shows the full queue (All + All podcasts + empty search).
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
                // Drag reorder uses full-queue indices; leave Edit while a chip/podcast/search filter is active.
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
            .onAppear {
                releaseQueuePodcastFilterIfFeedGone()
            }
            .onChange(of: store.feeds.map(\.id)) { _, _ in
                releaseQueuePodcastFilterIfFeedGone()
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
                            ? String(localized: "Allows drag reorder, Shuffle, Shuffle keep playing first, Reverse order, Sort by date, Sort by duration, Sort by title, Move playing to top, Move playing to bottom, and Move to top or bottom")
                            : String(localized: "Disables drag reorder, Shuffle, Shuffle keep playing first, Reverse order, Sort by date, Sort by duration, Sort by title, Move playing to top, Move playing to bottom, and Move to top or bottom")
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
                            copyQueue()
                        } label: {
                            Label("Copy queue", systemImage: "doc.plaintext")
                        }
                        // Full persisted queue (not chip/search). Queue lock does **not** disable.
                        .disabled(!canExportQueue)
                        .accessibilityLabel(String(localized: "Copy queue"))
                        .accessibilityHint(
                            String(localized: "Copies the full queue list to the pasteboard")
                        )

                        ShareLink(
                            item: queueShareText,
                            subject: Text(String(localized: "Queue"))
                        ) {
                            Label("Share queue", systemImage: "square.and.arrow.up")
                        }
                        // Same gates as Copy queue — full queue; lock does not block.
                        .disabled(!canExportQueue)
                        .accessibilityLabel(String(localized: "Share queue"))
                        .accessibilityHint(
                            String(localized: "Opens the system share sheet with the full queue list")
                        )

                        Button {
                            playRandomEpisode()
                        } label: {
                            Label("Play random", systemImage: "shuffle")
                        }
                        // Play random: uniform among full-queue playable; prefer unplayed; no confirm.
                        // Distinct from Shuffle (reorder). Queue lock does **not** disable.
                        .disabled(playRandomCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Play random"))
                        .accessibilityHint(String(localized: "Plays a random queued episode with playable media. Prefers unplayed when any remain."))

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
                            // Always confirm before sortQueueByTitle — reorders the full list.
                            showSortTitleAZQueueConfirm = true
                        } label: {
                            Label("Title A–Z", systemImage: "textformat.abc")
                        }
                        // Sort always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canSortByTitle)
                        .accessibilityLabel(String(localized: "Sort title A–Z"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then sorts the entire queue by title, A to Z")
                        )
                        Button {
                            // Always confirm before sortQueueByTitle — reorders the full list.
                            showSortTitleZAQueueConfirm = true
                        } label: {
                            Label("Title Z–A", systemImage: "textformat.abc")
                        }
                        // Sort always targets the full queue (not the filtered subset).
                        // Blocked when Queue locked (reorder-only) or fewer than 2 items.
                        .disabled(!canSortByTitle)
                        .accessibilityLabel(String(localized: "Sort title Z–A"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then sorts the entire queue by title, Z to A")
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
                        Button {
                            // Reuse moveQueueItemToBottom — no seek/stop; no confirm (single-item reorder).
                            if let current = playback.currentEpisode {
                                store.moveQueueItemToBottom(current)
                            }
                        } label: {
                            Label("Move playing to bottom", systemImage: "arrow.down.to.line")
                        }
                        // Enabled only when current episode is queued and not already last;
                        // blocked when Queue locked (reorder-only, same gate as Move playing to top).
                        .disabled(!canMovePlayingToBottom)
                        .accessibilityLabel(String(localized: "Move playing to bottom"))
                        .accessibilityHint(
                            String(localized: "Moves the currently playing episode to the end of the queue")
                        )
                        Button {
                            // Always confirm before markAllQueuePlayed() — never bulk-mark from the menu alone.
                            showMarkAllQueuePlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        // Mark all targets the full queue (not the filtered subset), skipping archived
                        // unplayed episodes. Queue lock does not block this playback-state action.
                        .disabled(markAllQueuePlayedCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Mark all as played"))
                        .accessibilityHint(
                            String(localized: "Marks unplayed, non-archived episodes in the full queue as played, ignoring filters")
                        )

                        Button {
                            // Always confirm before markAllQueueUnplayed() — never bulk-mark from the menu alone.
                            showMarkAllQueueUnplayedConfirm = true
                        } label: {
                            Label("Mark all as unplayed", systemImage: "circle")
                        }
                        // Mark all targets the full queue, including archived played episodes;
                        // Queue lock does not block this playback-state action.
                        .disabled(markAllQueueUnplayedCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Mark all as unplayed"))
                        .accessibilityHint(
                            String(localized: "Marks played episodes in the full queue, including archived episodes")
                        )

                        Button {
                            // Always confirm before archiveAllQueue() — never bulk-archive from the menu alone.
                            showArchiveAllQueueConfirm = true
                        } label: {
                            Label("Archive all", systemImage: "archivebox")
                        }
                        // Archive targets the full queue (not the played/podcast/search filtered subset).
                        // Queue lock does not block this archive-state action.
                        .disabled(archiveAllQueueCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Archive all"))
                        .accessibilityHint(
                            String(localized: "Archives non-archived episodes in the full queue; ignores filters")
                        )

                        Button(role: .destructive) {
                            // Always confirm before removePlayedFromQueue() — never remove from the menu alone.
                            showRemovePlayedConfirm = true
                        } label: {
                            Label("Remove played", systemImage: "checkmark.circle")
                        }
                        // Remove played always targets the full queue (not the filtered subset).
                        // Queue lock does **not** disable — reorder-only lock (same as Clear queue).
                        .disabled(!canRemovePlayed)
                        .accessibilityLabel(String(localized: "Remove played"))
                        .accessibilityHint(
                            String(localized: "Asks for confirmation, then removes played episodes from the queue")
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
                        String(localized: "Copy queue, share queue, play random, shuffle, shuffle keep playing first, reverse, sort by date, sort by duration, sort by title, move playing to top, move playing to bottom, mark all as played, mark all as unplayed, archive all, remove played, or clear the entire queue")
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
                "Mark all as played?",
                isPresented: $showMarkAllQueuePlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as played") {
                    store.markAllQueuePlayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Marks \(markAllQueuePlayedCandidatesCount) unplayed, non-archived episodes in the full queue as played. They leave the queue, and auto-delete after playing still applies when enabled. This ignores the Queue played/podcast/search filters."
                )
            }
            .confirmationDialog(
                "Mark all as unplayed?",
                isPresented: $showMarkAllQueueUnplayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as unplayed") {
                    store.markAllQueueUnplayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Marks \(markAllQueueUnplayedCandidatesCount) played episodes in the full queue as unplayed, including archived episodes. This does not delete downloads, remove episodes from the queue, stop playback, or unarchive episodes. It ignores the Queue played/podcast/search filters."
                )
            }
            .confirmationDialog(
                "Archive all?",
                isPresented: $showArchiveAllQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Archive all") {
                    store.archiveAllQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Archives \(archiveAllQueueCandidatesCount) non-archived episode(s) in the full queue (not only the current played/podcast/search filters). Archived does not mean played. Does not remove episodes from the queue, mark played, delete downloads, or stop playback."
                )
            }
            .confirmationDialog(
                "Remove played?",
                isPresented: $showRemovePlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove played", role: .destructive) {
                    store.removePlayedFromQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(playedInFullQueueCount) played episodes from the entire queue (not only the current filter). Does not stop playback, change progress, unmark played, or delete downloads."
                )
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
                "Sort queue title A–Z?",
                isPresented: $showSortTitleAZQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Title A–Z") {
                    store.sortQueueByTitle(ascending: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Sorts all \(store.queue.count) episodes in the entire queue by title, A to Z (not only the current filter). Empty titles go last. Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
                )
            }
            .confirmationDialog(
                "Sort queue title Z–A?",
                isPresented: $showSortTitleZAQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Title Z–A") {
                    store.sortQueueByTitle(ascending: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Sorts all \(store.queue.count) episodes in the entire queue by title, Z to A (not only the current filter). Empty titles go last. Does not stop playback, change progress, mark played, or delete downloads. The currently playing episode stays the same item and moves with its place in the list."
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

    /// Pasteboard copy of the **full** persisted queue (not chip/search). Read-only — does not reorder.
    private func copyQueue() {
        let text = queuePlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Queue copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does not reshuffle or otherwise mutate queue order beyond what `play` already does.
    /// Distinct from toolbar Shuffle / Shuffle (keep playing first).
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

/// Filter chip for Queue All / Unplayed / Played and podcast chips (mirrors Downloads).
private struct QueueFilterChip: View {
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
