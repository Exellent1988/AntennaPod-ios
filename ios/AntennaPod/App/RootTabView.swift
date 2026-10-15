import SwiftUI

/// String raw values so the selection can live in `@SceneStorage` (Android: NavDrawerFragment PREF_LAST_FRAGMENT_TAG).
enum RootTab: String, Hashable {
    case home, inbox, subscriptions, queue, downloads, settings
}

struct RootTabView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var parental: ParentalControls
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var notificationDeepLink = NewEpisodeNotificationCoordinator.deepLink
    @ObservedObject private var subscribeLink = SubscribeLinkRouter.shared
    /// Restores the last selected tab on relaunch, like Android `saveLastNavFragment`; defaults to Home.
    @SceneStorage("rootTab.selected") private var selectedTab: RootTab = .home
    /// Feed preview for an incoming subscribe link (`SubscribeLinkRouter`).
    @State private var subscribeLinkPreview: FeedPreviewRequest?
    /// `.settings` is not a tab: selecting it (Home gear, sync deep link) opens Settings as a sheet.
    @State private var showSettings = false
    /// DEBUG `-APDebugEpisodeDetail` only.
    @State private var debugEpisodeDetail: PodcastEpisode?
    /// DEBUG `-APDebugOpenFeed` only.
    @State private var debugFeed: PodcastFeed?
    /// DEBUG `-APDebugOpenDownloadLog` only.
    @State private var debugDownloadLog = false
    /// DEBUG `-APDebugOpenSwipeActions <list>` only.
    @State private var debugSwipeList: SwipeList?
    /// Bumped when the active tab is tapped again; a new id pops that tab back to its root screen.
    @State private var tabRootResets: [RootTab: Int] = [:]
    @StateObject private var tabReselect = TabReselectCenter()

    var body: some View {
        cannotStreamAlertStage(rootTabContent)
    }

    // Body split from the stream-error alert: one chain this long exceeds the CI type-checker time limit.
    private var rootTabContent: some View {
        deepLinkStage(settingsObserversStage(
            // Tab bar VoiceOver names come from Label titles (Localizable.xcstrings).
            rootTabs
                .environment(\.tabReselectCenter, tabReselect)
            .onChange(of: selectedTab) { previous, tab in
                guard tab == .settings else { return }
                selectedTab = previous == .settings ? .home : previous
                showSettings = true
            }
            .onAppear {
                // A pre-change SceneStorage value can still hold the old Settings tab.
                if selectedTab == .settings { selectedTab = .home }
                applyDebugLaunchArguments()
            }
            .sheet(isPresented: $debugDownloadLog) {
                NavigationStack {
                    DownloadErrorsView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { debugDownloadLog = false } } }
                }
            }
            .sheet(item: $debugFeed) { feed in
                NavigationStack {
                    FeedDetailView(feed: feed)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { debugFeed = nil } } }
                }
            }
            .sheet(item: $debugEpisodeDetail) { ep in
            NavigationStack {
                EpisodeDetailPager(episode: ep)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { debugEpisodeDetail = nil } } }
            }
        }
        .sheet(item: $debugSwipeList) { list in
            SwipeActionsSheet(list: list)
        }
        .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                // Launch: refresh subscribed feeds if the global interval is due.
                await FeedRefreshCoordinator.refreshAllFeedsIfDue(store: store, settings: settings)
                FeedRefreshCoordinator.scheduleBackgroundRefresh(interval: settings.refreshInterval)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    // Relock parental controls when leaving foreground (inactive/background).
                    playback.persistProgressBeforeBackground()
                    store.flushDeferredFeedsSave()
                    // Finish the queued playback.json write before iOS may suspend the app.
                    PodcastPersistence.flushPendingWrites()
                    parental.lockSession()
                    return
                }
                Task {
                    await FeedRefreshCoordinator.refreshAllFeedsIfDue(store: store, settings: settings)
                }
            }
        ))
    }

    /// Re-tapping the active tab pops it to root; at the root it scrolls the list to the top (TabRootScroll.swift).
    private var tabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == selectedTab {
                    if tabReselect.rootVisible.contains(tab) {
                        tabReselect.requestScrollToTop(tab)
                    } else {
                        tabRootResets[tab, default: 0] += 1
                    }
                }
                selectedTab = tab
            }
        )
    }

    // Split into stages: one modifier chain this long exceeds the CI type-checker time limit.
    @ViewBuilder
    private var rootTabs: some View {
        if horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
            RootSidebarView(selectedTab: $selectedTab, showSettings: $showSettings)
                .safeAreaInset(edge: .bottom) {
                    MiniPlayerView()
                }
        } else {
            phoneTabs
        }
    }

    private var phoneTabs: some View {
        TabView(selection: tabSelection) {
            HomeView(selectedTab: $selectedTab)
                .id(tabRootResets[.home, default: 0])
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(RootTab.home)
                .modifier(TabMiniPlayerInset(tab: .home, selectedTab: selectedTab))
            InboxView()
                .id(tabRootResets[.inbox, default: 0])
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                .tag(RootTab.inbox)
                .modifier(TabMiniPlayerInset(tab: .inbox, selectedTab: selectedTab))
                // Same source as Inbox list (`PodcastStore.inboxEpisodes`).
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(store.inboxEpisodes.count)
            SubscriptionsView()
                .id(tabRootResets[.subscriptions, default: 0])
                .tabItem {
                    Label("Subscriptions", systemImage: "square.stack.fill")
                }
                .tag(RootTab.subscriptions)
                .modifier(TabMiniPlayerInset(tab: .subscriptions, selectedTab: selectedTab))
            QueueView()
                .id(tabRootResets[.queue, default: 0])
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }
                .tag(RootTab.queue)
                .modifier(TabMiniPlayerInset(tab: .queue, selectedTab: selectedTab))
                // Full persisted queue (`PodcastStore.queue`), not chip/search filtered view.
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(store.queue.count)
            DownloadsView()
                .id(tabRootResets[.downloads, default: 0])
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(RootTab.downloads)
                .modifier(TabMiniPlayerInset(tab: .downloads, selectedTab: selectedTab))
                // Full completed catalog (`DownloadService.downloads`), not chip/search or in-progress.
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(downloads.downloads.count)
        }
    }

    private func settingsObserversStage<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: settings.refreshInterval) { _, interval in
            FeedRefreshCoordinator.scheduleBackgroundRefresh(interval: interval)
        }
        .onChange(of: settings.rewindSeconds) { _, _ in
            playback.applyRemoteSkipIntervals()
        }
        .onChange(of: settings.fastForwardSeconds) { _, _ in
            playback.applyRemoteSkipIntervals()
        }
        .onChange(of: settings.stereoToMonoEnabled) { _, _ in
            playback.applyAudioSessionConfiguration()
        }
        .onChange(of: settings.preservePitchEnabled) { _, _ in
            playback.applyTimePitchAlgorithm()
        }
        .onChange(of: settings.volumeBoostPercent) { _, _ in
            playback.applyVolumeBoost()
        }
        .onChange(of: settings.skipSilenceEnabled) { _, _ in
            playback.refreshAudioPipelineParameters()
        }
        .onChange(of: settings.skipSilenceLevel) { _, _ in
            playback.refreshAudioPipelineParameters()
        }
        .onChange(of: settings.volumeAdaptationMode) { _, _ in
            playback.refreshAudioPipelineParameters()
        }
        .onChange(of: settings.sleepTimerFadeEnabled) { _, _ in
            playback.applySleepTimerFadePreference()
        }
        .onChange(of: settings.playVideoAsAudioOnly) { _, _ in
            playback.applyAudioSessionConfiguration()
            playback.applyVideoAsAudioOnlyPolicy()
        }
        .onChange(of: settings.keepScreenOnWhilePlaying) { _, _ in
            playback.applyIdleTimerPolicy()
        }
        .onChange(of: playback.isPlaying) { _, _ in
            playback.applyIdleTimerPolicy()
        }
    }

    private func deepLinkStage<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: notificationDeepLink.inboxOpenToken) { _, token in
            guard token != nil else { return }
            clearCoveringPresentations()
            selectedTab = .inbox
            tabRootResets[.inbox, default: 0] += 1
        }
        .onChange(of: notificationDeepLink.downloadsOpenToken) { _, token in
            guard token != nil else { return }
            clearCoveringPresentations()
            selectedTab = .downloads
            tabRootResets[.downloads, default: 0] += 1
        }
        .onChange(of: notificationDeepLink.settingsSyncOpenToken) { _, token in
            guard token != nil else { return }
            // Keep an open Settings sheet (the sync sub-screen is pushed inside it); clear anything else.
            debugFeed = nil
            debugEpisodeDetail = nil
            subscribeLink.requestFullPlayerClose()
            selectedTab = .settings
        }
        .onChange(of: notificationDeepLink.feedOpenToken) { _, token in
            guard token != nil else { return }
            clearCoveringPresentations()
            selectedTab = .subscriptions
        }
        .onChange(of: subscribeLink.pendingFeedUrl) { _, _ in
            consumeSubscribeLink()
        }
        .onAppear {
            // Cold start: the link can arrive before this view observes the router.
            consumeSubscribeLink()
        }
        .sheet(item: $subscribeLinkPreview) { request in
            // Same gate as the Add sheet; Confirm Subscribe in the preview is gated again.
            if parental.needsPINForAddDiscover {
                ParentalPINPromptSheet(
                    title: String(localized: "Parental controls"),
                    message: String(localized: "Enter your PIN to add or discover podcasts."),
                    onCancel: { subscribeLinkPreview = nil },
                    onSuccess: { pin in parental.unlockSession(with: pin) }
                )
            } else {
                NavigationStack {
                    FeedPreviewView(request: request) {
                        subscribeLinkPreview = nil
                    }
                }
            }
        }
    }

    private func cannotStreamAlertStage<Content: View>(_ content: Content) -> some View {
        content
        .alert(
            "Cannot stream",
            isPresented: Binding<Bool>(
                get: { playback.lastError != nil },
                set: { (isPresented: Bool) in if !isPresented { playback.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                playback.lastError = nil
            }
        } message: {
            Text(playback.lastError ?? "")
        }
    }

    /// Already subscribed → open that podcast (same path as the player's Open podcast);
    /// otherwise show the normal feed preview, which only subscribes on Confirm.
    /// Closes the Full Player first and waits like `MiniPlayerView.openPodcastFromMiniPlayer`;
    /// sheets opened by other screens are not closed. Clearing the preview first lets the same
    /// link present again.
    /// A deep link must land on a visible screen with a way back. Android starts MainActivity with the
    /// target fragment on top of the back stack (system Back returns); here the Settings sheet, DEBUG sheets
    /// and the full player would otherwise cover the target tab, and a second sheet cannot be presented.
    private func clearCoveringPresentations() {
        showSettings = false
        debugFeed = nil
        debugEpisodeDetail = nil
        subscribeLink.requestFullPlayerClose()
    }

    private func consumeSubscribeLink() {
        guard let feedUrl = subscribeLink.pendingFeedUrl else { return }
        subscribeLink.pendingFeedUrl = nil
        clearCoveringPresentations()
        subscribeLinkPreview = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let feed = FeedURLNormalization.subscribedFeed(matching: feedUrl, in: store.feeds) {
                notificationDeepLink.openFeed(id: feed.id)
            } else {
                subscribeLinkPreview = FeedPreviewRequest(feedUrl: feedUrl)
            }
        }
    }

    /// Simulator screenshots: `-APDebugTab <home|inbox|subscriptions|queue|downloads>` picks the start
    /// tab, `-APDebugOpenSettings` opens the Settings sheet, `-APDebugOpenURL <url>` routes a deep link. Compiled out of release builds.
    private func applyDebugLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-APDebugTab"), i + 1 < args.count,
           let tab = RootTab(rawValue: args[i + 1]), tab != .settings {
            selectedTab = tab
        }
        if args.contains("-APDebugOpenSettings") {
            showSettings = true
        }
        // Launch-only: SubscriptionsView shows the grid without writing AppSettings
        // (the persisted setting stays `settings.subscriptionsDisplayMode`).
        if args.contains("-APDebugSubscriptionsGrid") {
            selectedTab = .subscriptions
        }
        if args.contains("-APDebugOpenDownloadLog") { debugDownloadLog = true }
        // -APDebugOpenSwipeActions <inbox|queue|episodes|downloads|history|favorites|feed>: that list's swipe sheet.
        if let i = args.firstIndex(of: "-APDebugOpenSwipeActions"), i + 1 < args.count {
            debugSwipeList = SwipeList(rawValue: args[i + 1])
        }
        // -APDebugOpenFeed opens the first podcast's page (add -APDebugOpenFeedSettings for its settings sheet).
        if args.contains("-APDebugOpenFeed"), let feed = store.feeds.first {
            debugFeed = feed
        }
        // Opens the episode detail pager on the newest episode of the first podcast.
        if args.contains("-APDebugEpisodeDetail"),
           let feed = store.feeds.first(where: { !$0.episodes.isEmpty }),
           let ep = feed.episodes.max(by: { ($0.pubDateEpochMs ?? 0) < ($1.pubDateEpochMs ?? 0) }) {
            debugEpisodeDetail = ep
        }
        // `-APDebugOpenURL <url>` routes a link 2.5 s (or `-APDebugOpenURLDelay <s>`) after launch, exactly like onOpenURL, so deep links can be
        // checked over an open sheet/player without the simulator's "Open in AntennaPod?" prompt.
        if let i = args.firstIndex(of: "-APDebugOpenURL"), i + 1 < args.count, let url = URL(string: args[i + 1]) {
            let customDelay = UserDefaults.standard.double(forKey: "APDebugOpenURLDelay")
            let delay = customDelay > 0 ? customDelay : 2.5
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !SubscribeLinkRouter.shared.handle(url: url) {
                    _ = PlaybackDeepLinkRouter.shared.handle(url: url)
                }
            }
        }
        // `-APDebugClosePlayer <s>` closes the full player after <s> seconds (same request deep links use), so
        // the tab layout under a live mini player can be screenshotted.
        let closePlayerAfter = UserDefaults.standard.double(forKey: "APDebugClosePlayer")
        if closePlayerAfter > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(closePlayerAfter * 1_000_000_000))
                subscribeLink.requestFullPlayerClose()
            }
        }
        #endif
    }
}

/// Mini player above the tab bar, like Android's PlayerFragment sitting over the BottomNavigationView.
/// On the TabView itself the inset was drawn over the tab bar: the compact row hid the tab labels and a
/// live mini player (progress + controls) covered the whole bar, so you could not switch tabs while listening.
/// Only the selected tab hosts it, so there is one MiniPlayerView (and one full-player sheet) at a time.
private struct TabMiniPlayerInset: ViewModifier {
    let tab: RootTab
    let selectedTab: RootTab

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == selectedTab {
                MiniPlayerView()
            }
        }
    }
}
