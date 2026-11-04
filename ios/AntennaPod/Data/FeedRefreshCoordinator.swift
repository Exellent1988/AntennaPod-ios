import BackgroundTasks
import Foundation

/// Coordinates automatic feed refresh (foreground due-check + BGAppRefreshTask).
///
/// Info.plist lists `UIBackgroundModes` `fetch` and `BGTaskSchedulerPermittedIdentifiers`
/// containing `backgroundTaskIdentifier`. iOS decides when (or whether) the task runs;
/// `earliestBeginDate` is only a lower bound.
@MainActor
enum FeedRefreshCoordinator {
    /// Must match Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let backgroundTaskIdentifier = "de.danoeh.antennapod.ios.refresh"

    static var isBackgroundRefreshConfigured: Bool {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        return ids.contains(backgroundTaskIdentifier)
    }

    /// Prevents overlapping auto-refresh from launch `.task` + foreground `onChange` + BG task.
    private static var isAutoRefreshInFlight = false
    private static var didRegister = false

    /// Must run before the app finishes launching (called from `AntennaPodApp.init`).
    static func registerBackgroundRefreshIfNeeded() {
        guard !didRegister, isBackgroundRefreshConfigured else { return }
        didRegister = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            MainActor.assumeIsolated { handle(task) }
        }
    }

    /// Earliest begin date for the next BG refresh; `nil` = do not schedule (manual interval).
    nonisolated static func nextBeginDate(interval: FeedRefreshInterval, lastRefresh: Date?, now: Date = Date()) -> Date? {
        guard let seconds = interval.timeInterval else { return nil }
        guard let last = lastRefresh else { return now }
        return max(now, last.addingTimeInterval(seconds))
    }

    /// Replace any pending request with one matching the interval (cancels on Manual).
    static func scheduleBackgroundRefresh(interval: FeedRefreshInterval) {
        guard didRegister else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        guard let begin = nextBeginDate(interval: interval, lastRefresh: AppServices.settings?.lastFeedRefreshAt) else { return }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = begin
        do { try BGTaskScheduler.shared.submit(request) } catch {
            // Simulator / Background App Refresh disabled: foreground due-check still applies.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        guard let store = AppServices.store, let settings = AppServices.settings else {
            task.setTaskCompleted(success: false); return
        }
        let work = Task { @MainActor in
            await refreshAllFeedsIfDue(store: store, settings: settings)
            scheduleBackgroundRefresh(interval: settings.refreshInterval)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// If the global refresh interval is due, refresh all feeds (`refreshAllFeeds` stamps completion).
    static func refreshAllFeedsIfDue(store: PodcastStore, settings: AppSettings) async {
        guard !isAutoRefreshInFlight else { return }
        guard settings.isFeedRefreshDue else { return }
        guard !store.feeds.isEmpty else { return }
        isAutoRefreshInFlight = true
        defer { isAutoRefreshInFlight = false }
        await store.refreshAllFeeds(userInitiated: false)
    }
}
