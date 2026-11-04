import SwiftUI

/// Pushed episode page with horizontal swipe between neighbouring episodes of the same podcast.
/// Android refs: app/src/main/java/de/danoeh/antennapod/ui/screen/episode/ItemPagerFragment.java
/// (ViewPager2 over the feed's items) and ItemFragment.java (header, play/stream + download buttons, description).
struct EpisodeDetailPager: View {
    @EnvironmentObject private var store: PodcastStore
    let episode: PodcastEpisode
    @State private var selectedId: String

    init(episode: PodcastEpisode) {
        self.episode = episode
        _selectedId = State(initialValue: episode.id)
    }

    /// Feed order (newest first, same as the feed screen). Falls back to the single episode.
    private var pages: [PodcastEpisode] {
        guard let feed = store.feed(containingEpisodeId: episode.id), !feed.episodes.isEmpty else {
            return [episode]
        }
        return feed.episodes.sorted { ($0.pubDateEpochMs ?? 0) > ($1.pubDateEpochMs ?? 0) }
    }

    private var feedTitle: String {
        store.feed(containingEpisodeId: episode.id).map { store.displayTitle(for: $0) } ?? ""
    }

    var body: some View {
        TabView(selection: $selectedId) {
            ForEach(pages) { page in
                EpisodeDetailView(episode: page, feedTitle: feedTitle)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(pages.first(where: { $0.id == selectedId })?.title ?? episode.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EpisodeDetailView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let episode: PodcastEpisode
    let feedTitle: String

    @State private var showShownotes = false
    @State private var confirmDeleteDownload = false

    private var plainDescription: String {
        guard let raw = episode.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if !feedTitle.isEmpty {
                    Text(feedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let ms = episode.pubDateEpochMs {
                    Text(Date(timeIntervalSince1970: TimeInterval(ms) / 1000), style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        _ = playback.play(episode: episode)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityAddTraits(.startsMediaSession)
                    EpisodeDownloadActions.button(episode: episode, downloads: downloads) { _ in
                        confirmDeleteDownload = true
                    }
                    .buttonStyle(.bordered)
                    if store.isInQueue(episode.id) {
                        Button {
                            store.removeFromQueue(episode)
                        } label: {
                            Label("Remove from queue", systemImage: "text.badge.minus")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            store.enqueue(episode)
                        } label: {
                            Label("Add to queue", systemImage: "text.append")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .labelStyle(.titleAndIcon)
                Divider()
                if plainDescription.isEmpty {
                    Text("No shownotes")
                        .foregroundStyle(.secondary)
                } else {
                    Text(plainDescription)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShownotes = true
                } label: {
                    Label("Shownotes", systemImage: "doc.text")
                }
            }
        }
        .sheet(isPresented: $showShownotes) {
            EpisodeDescriptionSheetView(episode: episode, feedTitle: feedTitle)
        }
        .confirmationDialog("Delete download?", isPresented: $confirmDeleteDownload, titleVisibility: .visible) {
            Button("Delete download", role: .destructive) { downloads.delete(episode) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
