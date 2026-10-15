import PodcastCore
import SwiftUI

/// iPad (regular width) navigation: a sidebar listing every Android drawer destination.
/// Android: NavDrawerFragment (app/src/main/java/de/danoeh/antennapod/ui/screen/drawer/NavDrawerFragment.java,
/// nav_drawer entries Home, Queue, Inbox, Episodes, Subscriptions, Downloads, History, Favorites,
/// Add podcast, Settings), shown permanently on tablets (main.xml sw600dp / drawer locked open).
/// iPhone keeps the 5-tab RootTabView without a More screen.
enum SidebarDestination: String, Hashable, CaseIterable, Identifiable {
    case home, queue, inbox, episodes, subscriptions, downloads, history, favorites
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .queue: "Queue"
        case .inbox: "Inbox"
        case .episodes: "Episodes"
        case .subscriptions: "Subscriptions"
        case .downloads: "Downloads"
        case .history: "History"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .queue: "list.bullet"
        case .inbox: "tray.fill"
        case .episodes: "rectangle.stack"
        case .subscriptions: "square.stack.fill"
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        case .favorites: "star.fill"
        }
    }

    init?(tab: RootTab) {
        switch tab {
        case .home: self = .home
        case .inbox: self = .inbox
        case .subscriptions: self = .subscriptions
        case .queue: self = .queue
        case .downloads: self = .downloads
        default: return nil
        }
    }

    var tab: RootTab? {
        switch self {
        case .home: .home
        case .inbox: .inbox
        case .subscriptions: .subscriptions
        case .queue: .queue
        case .downloads: .downloads
        default: nil
        }
    }
}

struct RootSidebarView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Binding var selectedTab: RootTab
    @Binding var showSettings: Bool
    @State private var selection: SidebarDestination? = .home
    @State private var showAddFeed = false
    /// Podcast picked from the sidebar's subscription list (Android drawer feed rows); nil = show `selection`.
    @State private var selectedFeedId: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SidebarDestination.allCases) { dest in
                        NavigationLink(value: dest) {
                            Label(dest.title, systemImage: dest.systemImage)
                                .badge(badge(for: dest))
                        }
                    }
                }
                // Android NavDrawerFragment / NavListAdapter: below the nav items the drawer lists the
                // subscriptions, grouped into tag folders (makeFlatDrawerData), each with its feed counter.
                if !store.feeds.isEmpty {
                    Section("Subscriptions") {
                        ForEach(store.allTags, id: \.self) { tag in
                            DisclosureGroup {
                                ForEach(sidebarFeeds(tagged: tag)) { feed in feedRow(feed) }
                            } label: {
                                Label(tag, systemImage: "folder")
                            }
                        }
                        ForEach(sidebarFeeds(tagged: nil)) { feed in feedRow(feed) }
                    }
                }
                Section {
                    Button { showAddFeed = true } label: {
                        Label("Add podcast", systemImage: "plus")
                    }
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("AntennaPod")
        } detail: {
            if let feedId = selectedFeedId, let feed = store.feeds.first(where: { $0.id == feedId }) {
                NavigationStack { FeedDetailView(feed: feed) }
                    .id(feedId)
            } else {
                detail(for: selection ?? .home)
                    .id(selection)
            }
        }
        .onAppear { selection = SidebarDestination(tab: selectedTab) ?? .home }
        // Deep links set selectedTab; mirror them into the sidebar.
        .onChange(of: selectedTab) { _, tab in
            if let dest = SidebarDestination(tab: tab) { selection = dest }
        }
        .onChange(of: selection) { _, dest in
            if dest != nil { selectedFeedId = nil }
            if let tab = dest?.tab, tab != selectedTab { selectedTab = tab }
        }
        .sheet(isPresented: $showAddFeed) { AddFeedView() }
    }

    private func badge(for dest: SidebarDestination) -> Int {
        switch dest {
        case .inbox: store.inboxEpisodes.count
        case .queue: store.queue.count
        case .downloads: downloads.downloads.count
        // Android NavListAdapter: Subscriptions row shows getFeedCounterSum().
        case .subscriptions: settings.subscriptionsCounterMode.badgeSum(store: store, downloads: downloads)
        default: 0
        }
    }

    /// Feeds with `tag` (nil = untagged) in the Subscriptions sort order (incl. Keep at top first).
    /// Android: the drawer sorts by UserPreferences.getFeedOrder(), the same setting as the subscriptions
    /// screen (DBReader.getNavDrawerData comparator, DBReader.java:690).
    private func sidebarFeeds(tagged tag: String?) -> [PodcastFeed] {
        let feeds = store.feeds.filter { feed in
            let tags = store.tags(for: feed.id)
            if let tag { return tags.contains { FeedTags.equal($0, tag) } }
            return tags.isEmpty
        }
        return SubscriptionsFeedOrder.sorted(feeds, by: settings.subscriptionsSort, store: store)
    }

    private func feedRow(_ feed: PodcastFeed) -> some View {
        Button {
            selection = nil
            selectedFeedId = feed.id
        } label: {
            Label(store.displayTitle(for: feed), systemImage: "dot.radiowaves.left.and.right")
                .badge(settings.subscriptionsCounterMode.counter(for: feed, store: store, downloads: downloads))
        }
        .foregroundStyle(selectedFeedId == feed.id ? Color.accentColor : Color.primary)
    }

    @ViewBuilder
    private func detail(for dest: SidebarDestination) -> some View {
        switch dest {
        case .home: HomeView(selectedTab: $selectedTab)
        case .queue: QueueView()
        case .inbox: InboxView()
        case .subscriptions: SubscriptionsView()
        case .downloads: DownloadsView()
        case .episodes: NavigationStack { AllEpisodesView() }
        case .history: NavigationStack { HistoryView() }
        case .favorites: NavigationStack { FavoritesView() }
        }
    }
}

extension SubscriptionsCounterMode {
    /// One podcast's counter (Android NavListAdapter bindFeedView `item.getCounter()`), using the
    /// PodcastCore FeedCounterRule (Android PodDBAdapter.getFeedCounters, PodDBAdapter.java:1339).
    @MainActor
    func counter(for feed: PodcastFeed, store: PodcastStore, downloads: DownloadService) -> Int {
        counter(for: feed, store: store, downloadedIds: Self.downloadedIds(downloads))
    }

    @MainActor
    static func downloadedIds(_ downloads: DownloadService) -> Set<String> {
        Set(downloads.downloads.map(\.episode.id))
    }

    @MainActor
    func counter(for feed: PodcastFeed, store: PodcastStore, downloadedIds: Set<String>) -> Int {
        if self == .none { return 0 }
        let facts = feed.episodes.map {
            FeedCounterEpisode(
                isPlayed: store.isPlayed($0.id),
                isArchived: store.isArchived($0.id),
                isDownloaded: downloadedIds.contains($0.id)
            )
        }
        return FeedCounterRule.count(coreKind, episodes: facts, isLocalFolderFeed: LocalFolderFeed.isLocalFolderFeed(feed))
    }

    /// Sum of the Subscriptions per-feed counters for this mode (Android NavDrawerFragment.getFeedCounterSum,
    /// app/.../ui/screen/drawer/NavDrawerFragment.java:342-351, sums `navDrawerData.feedCounters`).
    /// Android scope, followed here: those counters come from PodDBAdapter.getFeedCounters
    /// (storage/database/.../PodDBAdapter.java:1339) over EVERY subscribed feed (SELECT_WHERE_FEED_IS_SUBSCRIBED,
    /// :1381), taken in DBReader.getNavDrawerData (DBReader.java:677) BEFORE the subscriptions filter is applied
    /// to the feed list (:688). So the badge ignores the Subscriptions filters/search; archived (non-subscribed)
    /// feeds don't exist on iOS. iOS parental controls hide no feeds (PIN gates Add/Discover only), so `store.feeds`
    /// is exactly the subscribed set.
    @MainActor
    func badgeSum(store: PodcastStore, downloads: DownloadService) -> Int {
        if self == .none { return 0 }
        let ids = Self.downloadedIds(downloads)
        return store.feeds.reduce(0) { $0 + counter(for: $1, store: store, downloadedIds: ids) }
    }
}
