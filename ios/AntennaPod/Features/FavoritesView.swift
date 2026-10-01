import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: PodcastStore

    @State private var showClearFavoritesConfirm = false

    private var items: [FavoriteEpisode] {
        store.favoriteEpisodes
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Star episodes from a feed or the full player. Favorites keep their downloads when auto-delete after playing is on.")
                )
            } else {
                ForEach(items) { item in
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showClearFavoritesConfirm = true
                    } label: {
                        Label("Clear favorites", systemImage: "trash")
                    }
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
}
