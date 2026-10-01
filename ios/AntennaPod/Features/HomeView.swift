import SwiftUI

/// Landing tab: honest previews driven by Settings → Home layout (order + visibility).
struct HomeView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls
    @Binding var selectedTab: RootTab
    @State private var showDiscoverPINGate = false
    @State private var navigateToDiscover = false

    private let previewLimit = 5
    private let feedsLimit = 5

    private var continueItems: [HistoryEpisode] {
        Array(store.continueListeningEpisodes.prefix(previewLimit))
    }

    private var inboxItems: [InboxEpisode] {
        Array(store.inboxEpisodes.prefix(previewLimit))
    }

    private var queueItems: [PodcastEpisode] {
        Array(store.queue.prefix(previewLimit))
    }

    private var recentFeeds: [PodcastFeed] {
        Array(store.recentlyUpdatedFeeds.prefix(feedsLimit))
    }

    private var favoriteItems: [FavoriteEpisode] {
        Array(store.favoriteEpisodes.prefix(previewLimit))
    }

    /// Library content that would appear under visible non-Discover sections.
    private var hasVisibleLibraryContent: Bool {
        for id in settings.visibleHomeSections {
            switch id {
            case .continueListening:
                if !continueItems.isEmpty { return true }
            case .inbox:
                if !inboxItems.isEmpty { return true }
            case .queue:
                if !queueItems.isEmpty { return true }
            case .recentlyUpdated:
                if !recentFeeds.isEmpty { return true }
            case .favorites:
                if !favoriteItems.isEmpty { return true }
            case .discover:
                continue
            }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(settings.visibleHomeSections) { sectionId in
                    homeSection(for: sectionId)
                }

                if !hasVisibleLibraryContent {
                    ContentUnavailableView(
                        "Welcome",
                        systemImage: "house",
                        description: Text(welcomeDescription)
                    )
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .navigationDestination(isPresented: $navigateToDiscover) {
                TopListsView()
            }
            .sheet(isPresented: $showDiscoverPINGate) {
                ParentalPINPromptSheet(
                    title: "Parental controls",
                    message: "Enter your PIN to open Discover.",
                    onCancel: { showDiscoverPINGate = false },
                    onSuccess: { pin in
                        if parental.unlockSession(with: pin) {
                            showDiscoverPINGate = false
                            navigateToDiscover = true
                            return true
                        }
                        return false
                    }
                )
            }
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

    private var welcomeDescription: String {
        if settings.isHomeSectionVisible(.discover) {
            return "Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Or use Discover for Apple Charts. Customize sections under Settings → Home layout."
        }
        return "Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Customize sections under Settings → Home layout."
    }

    @ViewBuilder
    private func homeSection(for id: HomeSectionId) -> some View {
        switch id {
        case .discover:
            discoverSection
        case .continueListening:
            if !continueItems.isEmpty {
                continueSection
            }
        case .inbox:
            if !inboxItems.isEmpty {
                inboxSection
            }
        case .queue:
            if !queueItems.isEmpty {
                queueSection
            }
        case .recentlyUpdated:
            if !recentFeeds.isEmpty {
                recentlyUpdatedSection
            }
        case .favorites:
            if !favoriteItems.isEmpty {
                favoritesSection
            }
        }
    }

    @ViewBuilder
    private var discoverSection: some View {
        Section {
            HomeTopListsPreview()
        } header: {
            sectionHeader("Discover", systemImage: "chart.bar")
        } footer: {
            Button {
                if parental.needsPINForAddDiscover {
                    showDiscoverPINGate = true
                } else {
                    navigateToDiscover = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("See all charts")
                        .font(.footnote)
                    if parental.needsPINForAddDiscover {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var continueSection: some View {
        Section {
            ForEach(continueItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Last played"
                )
            }
        } header: {
            sectionHeader("Continue listening", systemImage: "play.circle")
        } footer: {
            NavigationLink {
                HistoryView()
            } label: {
                Text(store.continueListeningEpisodes.count > previewLimit ? "See all in History" : "Open History")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var inboxSection: some View {
        Section {
            ForEach(inboxItems) { item in
                EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
            }
        } header: {
            homeSectionLink(
                title: "New / Inbox",
                systemImage: "tray.fill",
                tab: .inbox,
                total: store.inboxEpisodes.count
            )
        } footer: {
            if store.inboxEpisodes.count > previewLimit {
                Button("See all in Inbox") {
                    selectedTab = .inbox
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        Section {
            ForEach(queueItems) { episode in
                EpisodeRow(
                    episode: episode,
                    feedTitle: store.feed(containingEpisodeId: episode.id)?.title ?? ""
                )
            }
        } header: {
            homeSectionLink(
                title: "Queue",
                systemImage: "list.bullet",
                tab: .queue,
                total: store.queue.count
            )
        } footer: {
            if store.queue.count > previewLimit {
                Button("See all in Queue") {
                    selectedTab = .queue
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var recentlyUpdatedSection: some View {
        Section {
            ForEach(recentFeeds) { feed in
                NavigationLink(value: feed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.title)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text("\(feed.episodes.count) episodes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let ms = feed.episodes.compactMap(\.pubDateEpochMs).max() {
                                Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Newest episode")
                            }
                        }
                    }
                }
            }
        } header: {
            sectionHeader("Recently updated", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            Button("See all subscriptions") {
                selectedTab = .subscriptions
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        Section {
            ForEach(favoriteItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.favoritedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Favorited"
                )
            }
        } header: {
            sectionHeader("Favorites", systemImage: "star")
        } footer: {
            NavigationLink {
                FavoritesView()
            } label: {
                Text(store.favoriteEpisodes.count > previewLimit ? "See all Favorites" : "Open Favorites")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    @ViewBuilder
    private func homeSectionLink(title: String, systemImage: String, tab: RootTab, total: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if total > 0 {
                Text("\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                selectedTab = tab
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title)")
        }
    }
}
