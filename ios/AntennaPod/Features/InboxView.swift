import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: PodcastStore

    private var items: [InboxEpisode] {
        store.inboxEpisodes
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Inbox empty",
                        systemImage: "tray",
                        description: Text("New and unplayed episodes from your subscriptions appear here.")
                    )
                } else {
                    ForEach(items) { item in
                        EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
                    }
                }
            }
            .navigationTitle("Inbox")
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
}
