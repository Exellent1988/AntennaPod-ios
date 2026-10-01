import SwiftUI

struct ArchivedView: View {
    @EnvironmentObject private var store: PodcastStore

    private var items: [ArchivedEpisode] {
        store.archivedEpisodes
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No archived episodes",
                    systemImage: "archivebox",
                    description: Text("Archive hides episodes from Inbox without marking them played. Restore them here or from a feed.")
                )
            } else {
                ForEach(items) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.archivedAtEpochMs) / 1000),
                        dateAccessibilityLabel: "Archived"
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            store.restore(item.episode.id)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}
