import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: PodcastStore

    private var items: [HistoryEpisode] {
        store.historyEpisodes
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Episodes you play or mark as played appear here, newest first.")
                )
            } else {
                ForEach(items) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                        dateAccessibilityLabel: "Last played"
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.removeFromHistory(item.episode.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if store.isPlayed(item.episode.id) {
                            Button {
                                store.markUnplayed(item.episode.id)
                            } label: {
                                Label("Mark unplayed", systemImage: "circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
