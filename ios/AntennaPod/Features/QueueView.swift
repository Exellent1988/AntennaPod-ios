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
                        description: Text("Add episodes from a podcast feed.")
                    )
                } else {
                    ForEach(store.queue) { episode in
                        EpisodeRow(episode: episode, feedTitle: "")
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.removeFromQueue(store.queue[index])
                        }
                    }
                }
            }
            .navigationTitle("Queue")
        }
    }
}
