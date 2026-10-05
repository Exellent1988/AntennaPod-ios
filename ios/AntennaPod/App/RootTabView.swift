import SwiftUI

enum RootTab: Hashable {
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
    @State private var selectedTab: RootTab = .home

    var body: some View {
        // Tab bar VoiceOver names come from Label titles (Localizable.xcstrings).
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(RootTab.home)
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                .tag(RootTab.inbox)
                // Same source as Inbox list (`PodcastStore.inboxEpisodes`).
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(store.inboxEpisodes.count)
            SubscriptionsView()
                .tabItem {
                    Label("Subscriptions", systemImage: "square.stack.fill")
                }
                .tag(RootTab.subscriptions)
            QueueView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }
                .tag(RootTab.queue)
                // Full persisted queue (`PodcastStore.queue`), not chip/search filtered view.
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(store.queue.count)
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(RootTab.downloads)
                // Full completed catalog (`DownloadService.downloads`), not chip/search or in-progress.
                // SwiftUI hides the badge when the count is 0; VoiceOver includes it.
                .badge(downloads.downloads.count)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .safeAreaInset(edge: .bottom) {
            MiniPlayerView()
        }
        .task {
            // Launch: refresh subscribed feeds if the global interval is due.
            await FeedRefreshCoordinator.refreshAllFeedsIfDue(store: store, settings: settings)
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
        .alert(
            "Cannot stream",
            isPresented: Binding(
                get: { playback.lastError != nil },
                set: { if !$0 { playback.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                playback.lastError = nil
            }
        } message: {
            Text(playback.lastError ?? "")
        }
    }
}
