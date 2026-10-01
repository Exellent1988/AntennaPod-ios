import SwiftUI

struct FeedDetailView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let feed: PodcastFeed
    @State private var showPerFeedSettings = false

    /// Live feed from the store when available (episodes refresh after pull/refresh).
    private var liveFeed: PodcastFeed {
        store.feeds.first(where: { $0.id == feed.id }) ?? feed
    }

    private var feedTags: [String] {
        store.tags(for: liveFeed.id)
    }

    var body: some View {
        List {
            if LocalFolderFeed.isLocalFolderFeed(liveFeed) {
                Section {
                    Label("Local folder feed", systemImage: "folder.fill")
                        .foregroundStyle(.orange)
                    Text("Episodes are audio files in a picked folder (mp3 / m4a / aac / wav / flac). No RSS and no network refresh — pull Refresh (swipe on Subscriptions) to re-scan. Unsubscribe releases folder access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !feedTags.isEmpty {
                Section("Tags") {
                    FlowTagRow(tags: feedTags)
                    Button("Manage tags…") {
                        showPerFeedSettings = true
                    }
                }
            }
            Section("Episodes") {
                ForEach(liveFeed.episodes) { episode in
                    EpisodeRow(episode: episode, feedTitle: liveFeed.title)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.toggleArchived(episode.id)
                            } label: {
                                Label(
                                    store.isArchived(episode.id) ? "Restore" : "Archive",
                                    systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                                )
                            }
                            .tint(store.isArchived(episode.id) ? .green : .orange)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                store.enqueue(episode)
                            } label: {
                                Label("Queue", systemImage: "text.append")
                            }
                            .tint(.purple)
                            if let url = episode.shareURL {
                                ShareLink(
                                    item: url,
                                    subject: Text(episode.title),
                                    message: Text(episode.title)
                                ) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.indigo)
                            }
                        }
                }
            }
        }
        .navigationTitle(liveFeed.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if let url = liveFeed.shareURL {
                        ShareLink(
                            item: url,
                            subject: Text(liveFeed.title),
                            message: Text(liveFeed.title)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share podcast")
                    }
                    Button {
                        showPerFeedSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Podcast settings")
                }
            }
        }
        .sheet(isPresented: $showPerFeedSettings) {
            NavigationStack {
                PerFeedSettingsView(feedId: feed.id, feedTitle: liveFeed.title)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPerFeedSettings = false }
                        }
                    }
            }
        }
    }
}


/// Simple wrapping tag chips (Feed detail header).
private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        // LazyVGrid keeps layout simple without a custom flow layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let episode: PodcastEpisode
    let feedTitle: String
    /// When set (e.g. History last-played), shown instead of the episode pub date.
    var dateOverride: Date? = nil
    var dateAccessibilityLabel: String? = nil

    private var state: EpisodePlaybackState {
        store.playbackState(for: episode.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(episode.title)
                    .font(.headline)
                Spacer(minLength: 8)
                if store.isFavorite(episode.id) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                if store.isArchived(episode.id) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Archived")
                }
                if state.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Played")
                }
            }
            if !feedTitle.isEmpty {
                Text(feedTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let dateOverride {
                Text(dateOverride, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(dateAccessibilityLabel ?? "Date")
            } else if let ms = episode.pubDateEpochMs {
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
                    playback.play(episode: episode)
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

                Button {
                    store.toggleFavorite(episode.id)
                } label: {
                    Label(
                        store.isFavorite(episode.id) ? "Unfavorite" : "Favorite",
                        systemImage: store.isFavorite(episode.id) ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.bordered)
                .tint(store.isFavorite(episode.id) ? .yellow : nil)

                Button {
                    store.toggleArchived(episode.id)
                } label: {
                    Label(
                        store.isArchived(episode.id) ? "Restore" : "Archive",
                        systemImage: store.isArchived(episode.id) ? "archivebox.fill" : "archivebox"
                    )
                }
                .buttonStyle(.bordered)
                .tint(store.isArchived(episode.id) ? .orange : nil)

                episodeShareControl
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 4)
        .opacity(store.isArchived(episode.id) ? 0.55 : 1)
        .contextMenu {
            if let url = episode.shareURL {
                ShareLink(
                    item: url,
                    subject: Text(episode.title),
                    message: Text(episode.title)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                store.toggleFavorite(episode.id)
            } label: {
                Label(
                    store.isFavorite(episode.id) ? "Unfavorite" : "Favorite",
                    systemImage: store.isFavorite(episode.id) ? "star.slash" : "star"
                )
            }
            Button {
                store.toggleArchived(episode.id)
            } label: {
                Label(
                    store.isArchived(episode.id) ? "Restore" : "Archive",
                    systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                )
            }
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    state.isPlayed ? "Mark unplayed" : "Mark played",
                    systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                )
            }
            Button {
                store.enqueue(episode)
            } label: {
                Label("Add to queue", systemImage: "text.append")
            }
        }
    }

    @ViewBuilder
    private var episodeShareControl: some View {
        if let url = episode.shareURL {
            ShareLink(
                item: url,
                subject: Text(episode.title),
                message: Text(episode.title)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        } else {
            Button {} label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(true)
        }
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
            return String(localized: "Resume")
        }
        return String(localized: "Play")
    }
}
