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
        // Launch maintenance once weak refs are wired (limit + played status available).
        downloads.runStorageMaintenance()
        // BGAppRefreshTask stub — Info.plist has no `fetch` mode (see FeedRefreshCoordinator).
        FeedRefreshCoordinator.registerBackgroundRefreshIfNeeded()
        // NWPathMonitor for Network / Downloads Wi‑Fi-only gates (auto / manual / stream).
        AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
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
        }
    }
}
