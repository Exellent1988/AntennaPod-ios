import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showMarkAllPlayedConfirm = false
    @State private var showEnqueueAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Inbox rows ordered by `AppSettings.inboxSort` (`pubDateEpochMs`).
    /// Missing dates sort last in both modes; stable tiebreaker is episode `id`
    /// (no `dateAdded` on `PodcastEpisode`). Does not mutate `PodcastStore.inboxEpisodes`
    /// (Home New preview stays newest-first).
    private var items: [InboxEpisode] {
        store.inboxEpisodes.sorted { lhs, rhs in
            switch settings.inboxSort {
            case .newestFirst:
                let l = lhs.episode.pubDateEpochMs ?? Int64.min
                let r = rhs.episode.pubDateEpochMs ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                let l = lhs.episode.pubDateEpochMs ?? Int64.max
                let r = rhs.episode.pubDateEpochMs ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            }
        }
    }

    private var isSearching: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Episodes from the **full Inbox catalog** (`store.inboxEpisodes`, newest-first) that are
    /// not already queued — same catalog as Mark all / Archive all, **not** library-search hits.
    /// Confirm count and `enqueueAllInbox()` share this eligibility. Menu disabled while searching.
    private var enqueueAllInboxCandidatesCount: Int {
        store.inboxEpisodes.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Visible Inbox rows for remaining-time: sorted list when **not** in library-search mode.
    /// While `.searchable` shows `LibrarySearchResultsView` (full library), the info bar is hidden —
    /// do not report full-Inbox / tab-badge totals over a different visible surface.
    private var visibleInboxForRemaining: [InboxEpisode] {
        isSearching ? [] : items
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Inbox list (sorted).
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide). Distinct from tab badge (full Inbox count).
    private var inboxRemainingInfoLabel: String? {
        guard !visibleInboxForRemaining.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: inboxRemainingSummary)
    }

    private var inboxRemainingAccessibilityLabel: String {
        guard let label = inboxRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Inbox remaining time \(label)")]
        let unknown = inboxRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var inboxRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: visibleInboxForRemaining.map(\.episode),
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
                // AntennaPod-like inbox info bar (visible sorted Inbox list remaining time).
                // Hidden while library search replaces the Inbox rows.
                if let remainingLabel = inboxRemainingInfoLabel {
                    Section {
                        Text(remainingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(inboxRemainingAccessibilityLabel)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }

                if isSearching {
                    LibrarySearchResultsView(query: debouncedQuery)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Inbox empty",
                        systemImage: "tray",
                        description: Text("New and unplayed episodes from your subscriptions appear here. Use search to find any episode or podcast in your library.")
                    )
                } else {
                    ForEach(items) { item in
                        EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
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
                                Button {
                                    store.archive(item.episode.id)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.markPlayed(item.episode.id)
                                } label: {
                                    Label("Mark played", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $settings.inboxSort) {
                            ForEach(InboxSort.allCases) { sort in
                                Label(sort.label, systemImage: sort.systemImage)
                                    .tag(sort)
                            }
                        } label: {
                            Text("Sort")
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "Sort inbox"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllInboxCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends Inbox episodes not already queued"))

                        Button {
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        .disabled(items.isEmpty)

                        Button {
                            store.archiveAllInbox()
                        } label: {
                            Label("Archive all", systemImage: "archivebox")
                        }
                        .disabled(items.isEmpty)
                    } label: {
                        Label("Inbox actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(items.isEmpty || isSearching)
                }
            }
            .confirmationDialog(
                "Add all to queue?",
                isPresented: $showEnqueueAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Add all to queue") {
                    store.enqueueAllInbox()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Appends \(enqueueAllInboxCandidatesCount) Inbox episodes to the end of the queue (newest first). Already queued episodes are skipped. Uses the full Inbox catalog (same as Mark all / Archive all), not library search. Queue lock does not block enqueue.")
            }
            .confirmationDialog(
                "Mark all as played?",
                isPresented: $showMarkAllPlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as played") {
                    store.markAllInboxPlayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Marks \(items.count) Inbox episodes as played. Episodes leave the Inbox; auto-delete after playing still applies when enabled.")
            }
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .searchable(text: $searchText, prompt: "Search library")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .refreshable {
                await store.refreshAllFeeds()
            }
            .overlay {
                if store.isLoading {
                    ProgressView("Refreshing feeds…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.ultraThinMaterial)
                }
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
