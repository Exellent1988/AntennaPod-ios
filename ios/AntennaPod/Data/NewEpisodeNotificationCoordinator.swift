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

    func openInbox() {
        inboxOpenToken = UUID()
    }

    func openDownloads() {
        downloadsOpenToken = UUID()
    }
}

/// Local UserNotifications for new episodes after feed refresh (no push / APNs).
///
/// **Permission:** requested once from Settings (toggle on) or the first refresh that finds
/// new episodes while the toggle is on and status is `.notDetermined`.
/// **Honesty:** posts when global or per-feed Always allows it **and** authorization
/// is `.authorized` / `.provisional`. Denied stays denied — Settings shows the real status.
/// Per-feed Never suppresses that feed even when global is on.
@MainActor
enum NewEpisodeNotificationCoordinator {
    static let categoryId = "NEW_EPISODES"
    static let destinationKey = "destination"
    static let destinationInbox = "inbox"
    static let feedIdKey = "feedId"

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
        center.setNotificationCategories([category, dlCategory])
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

    /// After refresh: request permission on first new-episode find if still undetermined, then notify.
    /// Per-feed `notifyOnNewEpisodes` Use global / Always / Never overrides the global toggle.
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

        for batch in flat {
            await postNotification(for: batch)
        }
    }

    private static func postNotification(for batch: NewEpisodeBatch) async {
        let content = UNMutableNotificationContent()
        content.title = batch.feedTitle.isEmpty ? "AntennaPod" : batch.feedTitle
        if batch.episodes.count == 1 {
            content.body = batch.episodes[0].title
        } else {
            content.body = "\(batch.episodes.count) new episodes"
        }
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            destinationKey: destinationInbox,
            feedIdKey: batch.feedId.uuidString,
            "feedUrl": batch.feedUrl
        ]

        // Unique per feed (stable `PodcastFeed.id`) so a later refresh replaces the prior banner.
        let id = "new-episodes.\(batch.feedId.uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
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
