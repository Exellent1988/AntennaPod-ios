import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: PodcastStore

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var items: [InboxEpisode] {
        store.inboxEpisodes
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    store.archive(item.episode.id)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !items.isEmpty, !isSearching {
                        Button("Archive all") {
                            store.archiveAllInbox()
                        }
                    }
                }
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
