import SwiftUI

struct AllEpisodesView: View {
    @EnvironmentObject private var store: PodcastStore
    @State private var searchText = ""

    private var items: [InboxEpisode] {
        let all = store.allEpisodes
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return all }
        return all.filter { item in
            item.episode.title.localizedCaseInsensitiveContains(q)
                || item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if items.isEmpty {
                if isFiltering {
                    ContentUnavailableView(
                        "No matching episodes",
                        systemImage: "magnifyingglass",
                        description: Text("No episodes match your filter.")
                    )
                } else {
                    ContentUnavailableView(
                        "No episodes yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Episodes from your subscriptions appear here, newest first.")
                    )
                }
            } else {
                ForEach(items) { item in
                    EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.toggleArchived(item.episode.id)
                            } label: {
                                Label(
                                    store.isArchived(item.episode.id) ? "Restore" : "Archive",
                                    systemImage: store.isArchived(item.episode.id)
                                        ? "arrow.uturn.backward" : "archivebox"
                                )
                            }
                            .tint(store.isArchived(item.episode.id) ? .green : .orange)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.togglePlayed(item.episode.id)
                            } label: {
                                Label(
                                    store.isPlayed(item.episode.id) ? "Mark unplayed" : "Mark played",
                                    systemImage: store.isPlayed(item.episode.id) ? "circle" : "checkmark.circle"
                                )
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter by title or podcast")
    }
}
