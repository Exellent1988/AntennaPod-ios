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
    @Binding var selectedTab: RootTab
    @Binding var showSettings: Bool
    @State private var selection: SidebarDestination? = .home
    @State private var showAddFeed = false

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
            detail(for: selection ?? .home)
                .id(selection)
        }
        .onAppear { selection = SidebarDestination(tab: selectedTab) ?? .home }
        // Deep links set selectedTab; mirror them into the sidebar.
        .onChange(of: selectedTab) { _, tab in
            if let dest = SidebarDestination(tab: tab) { selection = dest }
        }
        .onChange(of: selection) { _, dest in
            if let tab = dest?.tab, tab != selectedTab { selectedTab = tab }
        }
        .sheet(isPresented: $showAddFeed) { AddFeedView() }
    }

    private func badge(for dest: SidebarDestination) -> Int {
        switch dest {
        case .inbox: store.inboxEpisodes.count
        case .queue: store.queue.count
        case .downloads: downloads.downloads.count
        default: 0
        }
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
