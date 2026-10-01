import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService

    var body: some View {
        NavigationStack {
            List {
                if store.queue.isEmpty {
                    ContentUnavailableView(
                        "Queue empty",
                        systemImage: "list.bullet",
                        description: Text("Add episodes from a podcast feed. Edit mode lets you drag to reorder.")
                    )
                } else {
                    ForEach(store.queue) { episode in
                        EpisodeRow(
                            episode: episode,
                            feedTitle: store.feed(containingEpisodeId: episode.id)?.title ?? ""
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.removeFromQueue(episode)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.archive(episode.id)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove { source, destination in
                        store.moveQueue(from: source, to: destination)
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .disabled(store.queue.isEmpty)
                }
            }
        }
    }
}
