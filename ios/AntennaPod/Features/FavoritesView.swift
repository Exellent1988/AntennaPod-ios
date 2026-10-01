import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: PodcastStore

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearFavoritesConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full favorites catalog (newest first) — Clear favorites always uses this count.
    private var items: [FavoriteEpisode] {
        store.favoriteEpisodes
    }

    /// Visible favorites; empty query shows the full list.
    private var filteredItems: [FavoriteEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        if q.isEmpty { return base }
        return base.filter { item in
            if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
            return item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Star episodes from a feed or the full player. Favorites keep their downloads when auto-delete after playing is on.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching favorites",
                    systemImage: "magnifyingglass",
                    description: Text("No favorites match your search.")
                )
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.favoritedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Favorited")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.toggleFavorite(item.episode.id)
                        } label: {
                            Label("Unfavorite", systemImage: "star.slash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search favorites")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showClearFavoritesConfirm = true
                    } label: {
                        Label("Clear favorites", systemImage: "trash")
                    }
                    // Clear always targets the full favorites list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("Favorites actions", systemImage: "ellipsis.circle")
                }
                .disabled(items.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear favorites?",
            isPresented: $showClearFavoritesConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear favorites", role: .destructive) {
                store.clearFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(items.count) episodes from favorites. Does not delete downloads, archive, mark played, or clear the queue.")
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
