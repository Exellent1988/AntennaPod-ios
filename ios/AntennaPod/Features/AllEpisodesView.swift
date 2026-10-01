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
                }
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter by title or podcast")
    }
}
