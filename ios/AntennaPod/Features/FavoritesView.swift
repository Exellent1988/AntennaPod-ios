import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearFavoritesConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full favorites catalog (store order: newest favorited first) — Clear favorites always uses this count.
    private var items: [FavoriteEpisode] {
        store.favoriteEpisodes
    }

    /// Visible favorites ordered by `AppSettings.favoritesSort`.
    /// Sort key: `FavoriteEpisode.favoritedAtEpochMs` (`favoriteAtById` / `favorites.json`).
    /// Empty query shows the full list; sort applies to search-filtered results too.
    /// Does not mutate `PodcastStore.favoriteEpisodes` (Home Favorites preview / Clear favorites stay newest-first catalog).
    private var filteredItems: [FavoriteEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        let filtered: [FavoriteEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
                return item.feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.favoritesSort {
            case .newestFirst:
                if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                    return lhs.favoritedAtEpochMs > rhs.favoritedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                    return lhs.favoritedAtEpochMs < rhs.favoritedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            }
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
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.favoritesSort) {
                        ForEach(FavoritesSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort favorites")
            }
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
