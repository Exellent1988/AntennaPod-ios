import Foundation
import UserNotifications

/// Local UserNotifications for gpodder / Nextcloud login or sync failures (no push / APNs).
/// Reuses the same UNUserNotificationCenter permission path as new-episode / download-error alerts.
@MainActor
enum SyncErrorNotificationCoordinator {
    static let categoryId = "SYNC_ERROR"
    static let destinationKey = "destination"
    static let destinationSettingsSync = "settings-sync"

    /// Register category alongside other local-notification categories (idempotent with caller).
    static func registerCategory() {
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var next = existing
            next.insert(category)
            center.setNotificationCategories(next)
        }
    }

    /// When Settings toggle is on and system permission allows, post a local banner.
    /// `title` is the user-visible banner title (Login failed / Not logged in / Sync failed) —
    /// must not always say Sync failed for login failures.
    static func notifyIfNeeded(
        message: String,
        title: String = String(localized: "Sync failed"),
        settings: AppSettings?
    ) async {
        guard let settings, settings.notifyOnSyncErrors else { return }

        let short = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !short.isEmpty else { return }

        var status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        if status == .notDetermined {
            status = await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = trimmedTitle.isEmpty ? String(localized: "Sync failed") : String(trimmedTitle.prefix(80))
        content.body = String(short.prefix(120))
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            destinationKey: destinationSettingsSync
        ]

        let id = "sync-error.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Best-effort; ignore delivery failures in beta.
        }
    }
}
