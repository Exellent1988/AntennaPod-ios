import Foundation
import UIKit
import UserNotifications

/// Payload describing newly discovered episodes after a feed refresh (not first subscribe).
struct NewEpisodeBatch {
    let feedTitle: String
    let feedId: UUID
    let feedUrl: String
    let episodes: [PodcastEpisode]
}

/// Publishes a token when the user taps a new-episode notification (open Inbox).
@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    @Published private(set) var inboxOpenToken: UUID?
    @Published private(set) var downloadsOpenToken: UUID?
    @Published private(set) var settingsSyncOpenToken: UUID?
    /// Last token Settings already scrolled for. Lives on the router so a recreated
    /// Settings tab does not scroll again, and so consuming does not nil the token
    /// before the root tab switch observes it.
    private var consumedSettingsSyncOpenToken: UUID?
    /// Token + feed id for in-app “Open podcast” (full/mini player → Subscriptions → Feed detail).
    @Published private(set) var feedOpenToken: UUID?
    @Published private(set) var pendingFeedId: UUID?

    func openInbox() {
        inboxOpenToken = UUID()
    }

    func openDownloads() {
        downloadsOpenToken = UUID()
    }

    /// Open Settings tab and scroll to Sync (gpodder / Nextcloud).
    func openSettingsSync() {
        settingsSyncOpenToken = UUID()
    }

    /// True once per sync-error open. Does not clear the published token (RootTabView
    /// switches tabs from that change).
    func consumeSettingsSyncOpenToken() -> Bool {
        guard let token = settingsSyncOpenToken else { return false }
        guard token != consumedSettingsSyncOpenToken else { return false }
        consumedSettingsSyncOpenToken = token
        return true
    }

    /// Switch to Subscriptions and push Feed detail for `id` (best-effort).
    func openFeed(id: UUID) {
        pendingFeedId = id
        feedOpenToken = UUID()
    }
}

/// Local UserNotifications for new episodes after feed refresh (no push / APNs).
///
/// **Permission:** requested once from Settings (toggle on) or the first refresh that finds
/// new episodes while the toggle is on and status is `.notDetermined`.
/// **Honesty:** posts when the **global** Notify on new episodes toggle is on **and** the
/// per-feed override allows it (Use global / On) **and** authorization is `.authorized` /
/// `.provisional`. **Global is master** — per-feed On is ignored while global is off.
/// Per-feed Off suppresses that feed even when global is on. Denied stays denied — Settings
/// shows the real status (Allowed/Denied/Not determined), **Open iOS Settings** when denied,
/// and **Notifies / Does not notify** coverage (optional download-complete default off; no
/// server-side push).
/// **Aggregation:** one local banner per refresh (not one per feed) to avoid spam.
@MainActor
enum NewEpisodeNotificationCoordinator {
    static let categoryId = "NEW_EPISODES"
    static let destinationKey = "destination"
    static let destinationInbox = "inbox"
    static let feedIdKey = "feedId"
    /// Stable id so a later refresh replaces the prior aggregated banner.
    static let aggregateNotificationId = "new-episodes.aggregate"

    /// Shared router for notification taps → open Inbox (best-effort deep link).
    static let deepLink = NotificationDeepLinkRouter()

    private static var didConfigureCenter = false

    /// Register category + set delegate once (call from app launch).
    static func configureIfNeeded(delegate: UNUserNotificationCenterDelegate?) {
        guard !didConfigureCenter else { return }
        didConfigureCenter = true
        let center = UNUserNotificationCenter.current()
        if let delegate {
            center.delegate = delegate
        }
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let dlCategory = UNNotificationCategory(
            identifier: DownloadErrorNotificationCoordinator.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let syncCategory = UNNotificationCategory(
            identifier: SyncErrorNotificationCoordinator.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let sleepCategory = UNNotificationCategory(
            identifier: SleepTimerEndNotificationCoordinator.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let dlCompleteCategory = UNNotificationCategory(
            identifier: DownloadCompleteNotificationCoordinator.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, dlCategory, syncCategory, sleepCategory, dlCompleteCategory])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Request alert + sound + badge. Idempotent when already determined.
    @discardableResult
    static func requestPermissionIfNeeded() async -> UNAuthorizationStatus {
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }
        default:
            return status
        }
    }

    /// After refresh: request permission on first new-episode find if still undetermined, then
    /// post **one** aggregated local notification for all allowed batches.
    /// Per-feed `notifyOnNewEpisodes` Use global / On / Off (`PerFeedOverride`); **global is
    /// master** — include a batch only when `(feed override allows) && global enabled`.
    /// Feeds that did not refresh (Keep updated → Never skips bulk refresh) never appear in batches.
    static func handleNewEpisodes(
        _ batches: [NewEpisodeBatch],
        settings: AppSettings?,
        store: PodcastStore? = nil
    ) async {
        guard let settings else { return }
        let globalOn = settings.notifyOnNewEpisodes
        let flat = batches.filter { batch in
            guard !batch.episodes.isEmpty else { return false }
            if let store {
                return store.feedSettings(for: batch.feedId).allowsNotify(globalEnabled: globalOn)
            }
            return globalOn
        }
        guard !flat.isEmpty else { return }

        var status = await authorizationStatus()
        if status == .notDetermined {
            status = await requestPermissionIfNeeded()
        }
        guard status == .authorized || status == .provisional else { return }

        await postAggregatedNotification(batches: flat)
    }

    /// Banner count body: singular "1 new episode" vs plural "%lld new episodes".
    private static func newEpisodeCountBody(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 new episode")
        }
        return String(localized: "\(count) new episodes")
    }

    /// Fallback title when feed title is missing: singular vs plural for the batch size.
    private static func newEpisodeFallbackTitle(episodeCount: Int) -> String {
        episodeCount == 1
            ? String(localized: "New episode")
            : String(localized: "New episodes")
    }

    private static func postAggregatedNotification(batches: [NewEpisodeBatch]) async {
        let totalCount = batches.reduce(0) { $0 + $1.episodes.count }
        guard totalCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = categoryId

        var userInfo: [AnyHashable: Any] = [
            destinationKey: destinationInbox
        ]

        if batches.count == 1 {
            let batch = batches[0]
            let feed = batch.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            content.title = feed.isEmpty
                ? newEpisodeFallbackTitle(episodeCount: batch.episodes.count)
                : feed
            if batch.episodes.count == 1 {
                let title = batch.episodes[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
                content.body = title.isEmpty
                    ? newEpisodeCountBody(1)
                    : title
            } else {
                content.body = newEpisodeCountBody(batch.episodes.count)
            }
            userInfo[feedIdKey] = batch.feedId.uuidString
            userInfo["feedUrl"] = batch.feedUrl
        } else {
            // Multi-feed refresh: one banner — "N new episodes" (avoid per-feed spam).
            content.title = String(localized: "New episodes")
            content.body = newEpisodeCountBody(totalCount)
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: aggregateNotificationId,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Best-effort; ignore delivery failures in beta.
        }
    }

    static func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
