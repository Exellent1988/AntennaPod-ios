import SwiftUI

@main
struct AntennaPodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: PodcastStore
    @StateObject private var playback: PlaybackService
    @StateObject private var downloads: DownloadService
    @StateObject private var settings: AppSettings

    init() {
        let store = PodcastStore()
        let playback = PlaybackService()
        let downloads = DownloadService()
        let settings = AppSettings()
        playback.store = store
        playback.downloads = downloads
        playback.settings = settings
        downloads.store = store
        downloads.settings = settings
        store.settings = settings
        // Launch maintenance once weak refs are wired (limit + played status available).
        downloads.runStorageMaintenance()
        // BGAppRefreshTask stub — Info.plist has no `fetch` mode (see FeedRefreshCoordinator).
        FeedRefreshCoordinator.registerBackgroundRefreshIfNeeded()
        _store = StateObject(wrappedValue: store)
        _playback = StateObject(wrappedValue: playback)
        _downloads = StateObject(wrappedValue: downloads)
        _settings = StateObject(wrappedValue: settings)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(playback)
                .environmentObject(downloads)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
