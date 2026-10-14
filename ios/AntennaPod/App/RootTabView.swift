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
    @ObservedObject private var notificationDeepLink = NewEpisodeNotificationCoordinator.deepLink
    @ObservedObject private var subscribeLink = SubscribeLinkRouter.shared
    /// Restores the last selected tab on relaunch, like Android `saveLastNavFragment`; defaults to Home.
    @SceneStorage("rootTab.selected") private var selectedTab: RootTab = .home
    /// Feed preview for an incoming subscribe link (`SubscribeLinkRouter`).
    @State private var subscribeLinkPreview: FeedPreviewRequest?
    /// `.settings` is not a tab: selecting it (Home gear, sync deep link) opens Settings as a sheet.
    @State private var showSettings = false
    /// Bumped when the active tab is tapped again; a new id pops that tab back to its root screen.
    @State private var tabRootResets: [RootTab: Int] = [:]

    var body: some View {
        cannotStreamAlertStage(rootTabContent)
    }

    // Body split from the stream-error alert: one chain this long exceeds the CI type-checker time limit.
    private var rootTabContent: some View {
        deepLinkStage(settingsObserversStage(
            // Tab bar VoiceOver names come from Label titles (Localizable.xcstrings).
            rootTabs
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .safeAreaInset(edge: .bottom) {
                MiniPlayerView()
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

    /// Re-tapping the active tab pops it to root, like Android's bottom nav reselect.
    private var tabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == selectedTab { tabRootResets[tab, default: 0] += 1 }
                selectedTab = tab
            }
        )
    }

    // Split into stages: one modifier chain this long exceeds the CI type-checker time limit.
    private var rootTabs: some View {
        TabView(selection: tabSelection) {
            HomeView(selectedTab: $selectedTab)
                .id(tabRootResets[.home, default: 0])
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(RootTab.home)
            InboxView()
                .id(tabRootResets[.inbox, default: 0])
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                .tag(RootTab.inbox)
                // Same source as Inbox list (`PodcastStore.inboxEpisodes`).
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(store.inboxEpisodes.count)
            SubscriptionsView()
                .id(tabRootResets[.subscriptions, default: 0])
                .tabItem {
                    Label("Subscriptions", systemImage: "square.stack.fill")
                }
                .tag(RootTab.subscriptions)
            QueueView()
                .id(tabRootResets[.queue, default: 0])
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }
                .tag(RootTab.queue)
                // Full persisted queue (`PodcastStore.queue`), not chip/search filtered view.
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(store.queue.count)
            DownloadsView()
                .id(tabRootResets[.downloads, default: 0])
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(RootTab.downloads)
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
        .onChange(of: settings.volumeAdaptationEnabled) { _, _ in
            playback.applyAudioSessionConfiguration()
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
            selectedTab = .inbox
        }
        .onChange(of: notificationDeepLink.downloadsOpenToken) { _, token in
            guard token != nil else { return }
            selectedTab = .downloads
        }
        .onChange(of: notificationDeepLink.settingsSyncOpenToken) { _, token in
            guard token != nil else { return }
            selectedTab = .settings
        }
        .onChange(of: notificationDeepLink.feedOpenToken) { _, token in
            guard token != nil else { return }
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
    private func consumeSubscribeLink() {
        guard let feedUrl = subscribeLink.pendingFeedUrl else { return }
        subscribeLink.pendingFeedUrl = nil
        subscribeLink.requestFullPlayerClose()
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
    /// tab, `-APDebugOpenSettings` opens the Settings sheet. Compiled out of release builds.
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
        #endif
    }
}
