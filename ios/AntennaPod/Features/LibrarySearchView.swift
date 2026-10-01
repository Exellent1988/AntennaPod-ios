import SwiftUI

/// Local library search results (subscriptions + episodes). Not iTunes / online discovery.
struct LibrarySearchResultsView: View {
    @EnvironmentObject private var store: PodcastStore
    let query: String

    private var feeds: [PodcastFeed] {
        store.matchingFeeds(query: query)
    }

    private var episodes: [LibraryEpisodeHit] {
        store.matchingEpisodes(query: query)
    }

    private var isEmpty: Bool {
        feeds.isEmpty && episodes.isEmpty
    }

    var body: some View {
        if isEmpty {
            ContentUnavailableView(
                "No results",
                systemImage: "magnifyingglass",
                description: Text("No subscriptions or episodes match “\(displayQuery)”.")
            )
        } else {
            if !feeds.isEmpty {
                Section("Podcasts") {
                    ForEach(feeds) { feed in
                        NavigationLink(value: feed) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.title)
                                    .font(.headline)
                                Text("\(feed.episodes.count) episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !episodes.isEmpty {
                Section("Episodes") {
                    ForEach(episodes) { hit in
                        EpisodeRow(episode: hit.episode, feedTitle: hit.feedTitle)
                    }
                }
            }
        }
    }

    private var displayQuery: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? query : trimmed
    }
}
