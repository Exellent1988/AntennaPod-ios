import Foundation

/// Coordinates automatic feed refresh (foreground due-check + optional BG stub).
///
/// **Background App Refresh:** Info.plist currently only lists `UIBackgroundModes` → `audio`
/// (playback / background downloads). It does **not** include `fetch`, nor
/// `BGTaskSchedulerPermittedIdentifiers`. Registering `BGAppRefreshTask` without those
/// keys would never run (and can crash at schedule time). This type therefore **stubs**
/// BG registration — call sites document the gap; enable later by adding `fetch` +
/// permitted identifiers, then implementing `registerBackgroundRefreshIfNeeded()`.
@MainActor
enum FeedRefreshCoordinator {
    /// Task id reserved for a future BGAppRefreshTask (must match Info.plist when enabled).
    static let backgroundTaskIdentifier = "de.danoeh.antennapod.ios.refresh"

    /// Whether Info.plist / entitlements already allow BGAppRefreshTask registration.
    /// Always `false` for this beta slice (no `fetch` mode).
    static var isBackgroundRefreshConfigured: Bool { false }

    /// Prevents overlapping auto-refresh from launch `.task` + foreground `onChange`.
    private static var isAutoRefreshInFlight = false

    /// No-op stub. Does not call `BGTaskScheduler` (would require Info.plist changes).
    static func registerBackgroundRefreshIfNeeded() {
        // Stubbed: UIBackgroundModes lacks `fetch`; BGTaskSchedulerPermittedIdentifiers absent.
        // When enabling: import BackgroundTasks, register `backgroundTaskIdentifier`,
        // schedule BGAppRefreshTaskRequest, and in the handler call store.refreshAllFeeds()
        // then markFeedRefreshCompleted() / setTaskCompleted.
    }

    /// Schedule next BG refresh — stubbed (see `isBackgroundRefreshConfigured`).
    static func scheduleBackgroundRefresh(interval: FeedRefreshInterval) {
        _ = interval
        // Stubbed until Info.plist allows BGAppRefreshTask.
    }

    /// If the global refresh interval is due, refresh all feeds (`refreshAllFeeds` stamps completion).
    static func refreshAllFeedsIfDue(store: PodcastStore, settings: AppSettings) async {
        guard !isAutoRefreshInFlight else { return }
        guard settings.isFeedRefreshDue else { return }
        guard !store.feeds.isEmpty else { return }
        isAutoRefreshInFlight = true
        defer { isAutoRefreshInFlight = false }
        await store.refreshAllFeeds()
    }
}
