import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showMarkAllPlayedConfirm = false

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

    var body: some View {
        NavigationStack {
            List {
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
                    .accessibilityLabel("Sort inbox")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
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
