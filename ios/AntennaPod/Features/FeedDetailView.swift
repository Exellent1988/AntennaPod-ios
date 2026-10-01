import SwiftUI

struct FeedDetailView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let feed: PodcastFeed

    var body: some View {
        List(feed.episodes) { episode in
            EpisodeRow(episode: episode, feedTitle: feed.title)
        }
        .navigationTitle(feed.title)
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let episode: PodcastEpisode
    let feedTitle: String

    private var state: EpisodePlaybackState {
        store.playbackState(for: episode.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(episode.title)
                    .font(.headline)
                Spacer(minLength: 8)
                if state.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Played")
                }
            }
            if let ms = episode.pubDateEpochMs {
                Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if progressFraction > 0, !state.isPlayed {
                ProgressView(value: progressFraction)
                    .tint(.accentColor)
            }
            HStack {
                Button {
                    let local = downloads.localURL(for: episode)
                    playback.play(episode: episode, fileURL: local)
                } label: {
                    Label(resumeLabel, systemImage: "play.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await downloads.download(episode) }
                } label: {
                    if downloads.inProgress.contains(episode.id) {
                        ProgressView()
                    } else if downloads.isDownloaded(episode) {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episode.downloadUrl == nil || downloads.inProgress.contains(episode.id))

                Button {
                    store.enqueue(episode)
                } label: {
                    Label("Queue", systemImage: "text.append")
                }
                .buttonStyle(.bordered)

                Button {
                    store.togglePlayed(episode.id)
                } label: {
                    Label(
                        state.isPlayed ? "Mark unplayed" : "Mark played",
                        systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                    )
                }
                .buttonStyle(.bordered)
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 4)
    }

    private var progressFraction: Double {
        let duration = state.durationSeconds
        let position = state.positionSeconds
        guard duration.isFinite, duration > 0, position > 0 else {
            return 0
        }
        return min(1, position / duration)
    }

    private var resumeLabel: String {
        if !state.isPlayed, state.positionSeconds > 1 {
            return "Resume"
        }
        return "Play"
    }
}
