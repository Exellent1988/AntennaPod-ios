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
/// **Honesty:** posts when global or per-feed Always allows it **and** authorization
/// is `.authorized` / `.provisional`. Denied stays denied — Settings shows the real status.
/// Per-feed Never suppresses that feed even when global is on.
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
        center.setNotificationCategories([category, dlCategory, syncCategory])
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
    /// Per-feed `notifyOnNewEpisodes` Use global / Always / Never overrides the global toggle.
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
            content.title = batch.feedTitle.isEmpty
                ? String(localized: "New episodes")
                : batch.feedTitle
            if batch.episodes.count == 1 {
                let title = batch.episodes[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
                content.body = title.isEmpty
                    ? String(localized: "\(1) new episodes")
                    : title
            } else {
                content.body = String(localized: "\(batch.episodes.count) new episodes")
            }
            userInfo[feedIdKey] = batch.feedId.uuidString
            userInfo["feedUrl"] = batch.feedUrl
        } else {
            // Multi-feed refresh: one banner — "N new episodes" (avoid per-feed spam).
            content.title = String(localized: "New episodes")
            content.body = String(localized: "\(totalCount) new episodes")
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
