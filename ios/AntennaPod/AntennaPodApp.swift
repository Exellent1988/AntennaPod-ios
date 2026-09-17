import SwiftUI

@main
struct AntennaPodApp: App {
    @StateObject private var store = PodcastStore()
    @StateObject private var playback = PlaybackService()
    @StateObject private var downloads = DownloadService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(playback)
                .environmentObject(downloads)
        }
    }
}
