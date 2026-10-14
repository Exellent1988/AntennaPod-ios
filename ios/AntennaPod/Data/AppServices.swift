import Foundation

/// Weak registry of the app-wide services built in `AntennaPodApp.init`, so non-SwiftUI entry
/// points (CarPlay scene, BGTaskScheduler handlers) can reach the same instances.
@MainActor
enum AppServices {
    static weak var store: PodcastStore?
    static weak var playback: PlaybackService?
    static weak var downloads: DownloadService?
    static weak var settings: AppSettings?
    /// True while a CarPlay interface is connected (Android `UI_MODE_TYPE_CAR`: next = skip episode).
    static var isCarPlayConnected = false
}
