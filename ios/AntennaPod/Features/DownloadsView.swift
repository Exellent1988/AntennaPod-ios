import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var playback: PlaybackService

    var body: some View {
        NavigationStack {
            List {
                if downloads.downloads.isEmpty {
                    ContentUnavailableView(
                        "No downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Downloaded episodes will appear here for offline playback.")
                    )
                } else {
                    ForEach(downloads.downloads) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.episode.title)
                                    .font(.headline)
                                Text(item.localFileURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                playback.play(episode: item.episode, fileURL: item.localFileURL)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            downloads.delete(downloads.downloads[index].episode)
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            if let error = downloads.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
    }
}
