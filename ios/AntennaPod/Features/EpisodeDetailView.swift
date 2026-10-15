import SwiftUI

/// Pushed episode page with horizontal swipe between neighbouring episodes of the same podcast.
/// Android refs: app/src/main/java/de/danoeh/antennapod/ui/screen/episode/ItemPagerFragment.java
/// (ViewPager2 over the feed's items) and ItemFragment.java (header, play/stream + download buttons, description).
/// List an episode row belongs to, in that list's own order. Each episode list (Queue, Inbox, Episodes,
/// Downloads, History, Favorites, Archive, feed page) sets it so the detail pager swipes through the same list,
/// like Android's `ItemPagerFragment.newInstance(List<FeedItem> allItems, FeedItem currentItem)`.
private struct EpisodePagerListKey: EnvironmentKey {
    static let defaultValue: [PodcastEpisode]? = nil
}

extension EnvironmentValues {
    var episodePagerList: [PodcastEpisode]? {
        get { self[EpisodePagerListKey.self] }
        set { self[EpisodePagerListKey.self] = newValue }
    }
}

extension View {
    func episodePagerList(_ list: [PodcastEpisode]) -> some View {
        environment(\.episodePagerList, list)
    }
}

/// Pushed episode page with horizontal swipe between neighbouring episodes of the list it was opened from.
/// Android refs: app/src/main/java/de/danoeh/antennapod/ui/screen/episode/ItemPagerFragment.java
/// (ViewPager2 over the ids of the opening list, `setOffscreenPageLimit(1)`, toolbar menu `feeditem_options`
/// rebuilt for the current page) and ItemFragment.java (header, play/stream + download buttons, description).
struct EpisodeDetailPager: View {
    @EnvironmentObject private var store: PodcastStore
    let episode: PodcastEpisode
    let list: [PodcastEpisode]?
    @State private var selectedId: String

    /// Pages around the opened episode, like ViewPager2 keeping a bounded window instead of thousands of pages.
    static let pageWindow = 100

    init(episode: PodcastEpisode, list: [PodcastEpisode]? = nil) {
        self.episode = episode
        self.list = list
        _selectedId = State(initialValue: episode.id)
    }

    /// Opening list order; without one, feed order (newest first, same as the feed screen).
    private var allPages: [PodcastEpisode] {
        if let list, list.contains(where: { $0.id == episode.id }) { return list }
        guard let feed = store.feed(containingEpisodeId: episode.id), !feed.episodes.isEmpty else {
            return [episode]
        }
        return feed.episodes.sorted { ($0.pubDateEpochMs ?? 0) > ($1.pubDateEpochMs ?? 0) }
    }

    private var pages: [PodcastEpisode] {
        let all = allPages
        guard all.count > Self.pageWindow, let i = all.firstIndex(where: { $0.id == episode.id }) else { return all }
        let lo = max(0, min(i - Self.pageWindow / 2, all.count - Self.pageWindow))
        return Array(all[lo..<(lo + Self.pageWindow)])
    }

    private var current: PodcastEpisode {
        let id = selectedId
        return pages.first(where: { $0.id == id }) ?? episode
    }

    private func feedTitle(_ e: PodcastEpisode) -> String {
        store.feed(containingEpisodeId: e.id).map { store.displayTitle(for: $0) } ?? ""
    }

    var body: some View {
        let pages = pages
        let all = allPages
        TabView(selection: $selectedId) {
            ForEach(pages) { page in
                EpisodeDetailView(episode: page, feedTitle: feedTitle(page))
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if all.count > 1, let pos = all.firstIndex(where: { $0.id == selectedId }) {
                Text("\(pos + 1) of \(all.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 4)
                    .accessibilityLabel(Text("Episode \(pos + 1) of \(all.count)"))
                    .accessibilityHint(String(localized: "Swipe left or right to open the neighbouring episode"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EpisodeDetailActionsMenu(episode: current, feedTitle: feedTitle(current))
            }
        }
    }
}

/// Toolbar actions for the current page. Android: app/src/main/res/menu/feeditem_options.xml handled by
/// FeedItemMenuHandler (play/stream, download/delete, add/remove queue, mark played/unplayed,
/// add/remove favorite, share, visit website, open podcast).
struct EpisodeDetailActionsMenu: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    let episode: PodcastEpisode
    let feedTitle: String
    @State private var showPodcast = false

    var body: some View {
        let feed = store.feed(containingEpisodeId: episode.id)
        Menu {
            Button {
                _ = playback.play(episode: episode)
            } label: {
                Label(downloads.isDownloaded(episode) ? "Play" : "Stream", systemImage: "play.fill")
            }
            if downloads.isDownloaded(episode) {
                Button(role: .destructive) { downloads.delete(episode) } label: {
                    Label("Delete download", systemImage: "trash")
                }
            } else {
                Button { Task { await downloads.download(episode) } } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            if store.isInQueue(episode.id) {
                Button { store.removeFromQueue(episode) } label: {
                    Label("Remove from queue", systemImage: "text.badge.minus")
                }
            } else {
                Button { store.enqueue(episode) } label: {
                    Label("Add to queue", systemImage: "text.append")
                }
            }
            Button { store.togglePlayed(episode.id) } label: {
                store.isPlayed(episode.id)
                    ? Label("Mark as unplayed", systemImage: "circle")
                    : Label("Mark as played", systemImage: "checkmark.circle")
            }
            Button { store.toggleFavorite(episode.id) } label: {
                store.isFavorite(episode.id)
                    ? Label("Remove from favorites", systemImage: "star.slash")
                    : Label("Add to favorites", systemImage: "star")
            }
            Divider()
            if let url = episode.shareURL(feed: feed) {
                ShareLink(item: url, subject: Text(episode.title),
                          message: Text(episode.shareMessage(feedTitle: feedTitle))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if let url = episode.websiteURL {
                Link(destination: url) { Label("Visit website", systemImage: "safari") }
            }
            if feed != nil {
                Button { showPodcast = true } label: {
                    Label("Go to podcast", systemImage: "square.stack")
                }
            }
        } label: {
            Label("Episode actions", systemImage: "ellipsis.circle")
        }
        .navigationDestination(isPresented: $showPodcast) {
            if let feed { FeedDetailView(feed: feed) }
        }
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

    @ViewBuilder private var downloadButton: some View {
        if downloads.isWaitingDownload(episodeId: episode.id) {
            EpisodeDetailActionButton("episodeDetail.waiting", systemImage: "clock",
                                      accessibility: String(localized: "Cancel download")) {
                downloads.cancelDownload(episode)
            }
        } else if downloads.inProgress.contains(episode.id) {
            EpisodeDetailActionButton("episodeDetail.cancel", systemImage: "xmark.circle",
                                      accessibility: String(localized: "Cancel download")) {
                downloads.cancelDownload(episode)
            }
        } else if downloads.isDownloaded(episode) {
            EpisodeDetailActionButton("episodeDetail.delete", systemImage: "trash",
                                      accessibility: String(localized: "Delete download")) {
                confirmDeleteDownload = true
            }
            .tint(.red)
        } else {
            EpisodeDetailActionButton("episodeDetail.download", systemImage: "arrow.down.circle",
                                      accessibility: String(localized: "Download")) {
                Task { await downloads.download(episode) }
            }
        }
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
                // Android ItemFragment: a row of equal-width buttons, icon above a short one-line label.
                HStack(spacing: 8) {
                    EpisodeDetailActionButton(
                        "episodeDetail.play", systemImage: "play.fill",
                        accessibility: String(localized: "Play"), prominent: true
                    ) {
                        _ = playback.play(episode: episode)
                    }
                    .accessibilityAddTraits(.startsMediaSession)
                    if EpisodeDownloadActions.canManageDownload(for: episode) {
                        downloadButton
                    }
                    if store.isInQueue(episode.id) {
                        EpisodeDetailActionButton(
                            "episodeDetail.queued", systemImage: "text.badge.checkmark",
                            accessibility: String(localized: "Remove from queue")
                        ) {
                            store.removeFromQueue(episode)
                        }
                    } else {
                        EpisodeDetailActionButton(
                            "episodeDetail.queue", systemImage: "text.append",
                            accessibility: String(localized: "Add to queue")
                        ) {
                            store.enqueue(episode)
                        }
                    }
                }
                // Icons + one-line labels stay legible up to AX3; beyond that the labels only scale.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .fixedSize(horizontal: false, vertical: true)
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

/// Equal-width episode detail button: icon above a short one-line label that scales down instead of
/// hyphenating (Android ItemFragment butAction1/butAction2). Full action text is the accessibility label.
struct EpisodeDetailActionButton: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let accessibility: String
    var prominent = false
    let action: () -> Void

    init(_ titleKey: LocalizedStringKey, systemImage: String, accessibility: String,
         prominent: Bool = false, action: @escaping () -> Void) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.accessibility = accessibility
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .imageScale(.medium)
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .allowsTightening(true)
                    // Label text caps at xxxLarge so "Warteschlange" stays whole; the icon keeps growing.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .padding(.vertical, 4)
        }
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityLabel(accessibility)
        Group {
            if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
        }
    }
}
