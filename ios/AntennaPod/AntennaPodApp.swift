import SwiftUI

@main
struct AntennaPodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: PodcastStore
    @StateObject private var playback: PlaybackService
    @StateObject private var downloads: DownloadService
    @StateObject private var settings: AppSettings
    @StateObject private var gpodder: GpodderSyncService
    @StateObject private var parental: ParentalControls

    init() {
        let store = PodcastStore()
        let playback = PlaybackService()
        let downloads = DownloadService()
        let settings = AppSettings()
        let gpodder = GpodderSyncService()
        let parental = ParentalControls()
        playback.store = store
        playback.downloads = downloads
        playback.settings = settings
        downloads.store = store
        downloads.settings = settings
        gpodder.settings = settings
        store.settings = settings
        store.downloads = downloads
        store.playback = playback
        // Previous run's episode, paused in the mini player (no player / audio session yet).
        // Before the deep-link attach so a queued cold-start Play can start it.
        playback.restoreLastEpisodeIfPossible()
        // Launch maintenance once weak refs are wired (limit + played status available).
        downloads.runStorageMaintenance()
        // History size cap (needs settings); no-op when Unlimited.
        store.trimHistoryToSizeLimitIfNeeded()
        // Homescreen widget Continue-listening snapshot (needs store.playback wired).
        store.publishWidgetSnapshot()
        // Apple Watch companion: WCSession for snapshot push + play remote.
        WatchCompanionBridge.shared.activateIfNeeded()
        // BGAppRefreshTask stub — Info.plist has no `fetch` mode (see FeedRefreshCoordinator).
        FeedRefreshCoordinator.registerBackgroundRefreshIfNeeded()
        // NWPathMonitor for Network / Downloads Wi‑Fi-only gates (auto / manual / stream).
        AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
        // Siri / URL-scheme playback actions (antennapod://play etc.).
        PlaybackDeepLinkRouter.shared.attach(playback: playback)
        _store = StateObject(wrappedValue: store)
        _playback = StateObject(wrappedValue: playback)
        _downloads = StateObject(wrappedValue: downloads)
        _settings = StateObject(wrappedValue: settings)
        _gpodder = StateObject(wrappedValue: gpodder)
        _parental = StateObject(wrappedValue: parental)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(playback)
                .environmentObject(downloads)
                .environmentObject(settings)
                .environmentObject(gpodder)
                .environmentObject(parental)
                .preferredColorScheme(settings.theme.colorScheme)
                .modifier(OptionalAccentTint(tint: settings.accentColor.tintColor))
                .onOpenURL { url in
                    // Subscribe links first; playback links (antennapod://play …) unchanged.
                    if SubscribeLinkRouter.shared.handle(url: url) {
                        return
                    }
                    _ = PlaybackDeepLinkRouter.shared.handle(url: url)
                }
                .onAppear {
                    // Re-attach in case a cold-start intent queued before init finished wiring.
                    PlaybackDeepLinkRouter.shared.attach(playback: playback)
                }
        }
        .commands {
            PlaybackKeyboardCommands(playback: playback)
        }
    }
}


/// Applies `.tint` only when Settings chose a named accent (System = no override).
private struct OptionalAccentTint: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        if let tint {
            content.tint(tint)
        } else {
            content
        }
    }
}
