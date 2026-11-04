import Foundation
import UserNotifications

/// Local UserNotifications for download **failures** only (no push / APNs).
/// Success banners are optional via `DownloadCompleteNotificationCoordinator` (separate toggle, default off).
/// Reuses the same UNUserNotificationCenter permission path as new-episode alerts.
@MainActor
enum DownloadErrorNotificationCoordinator {
    static let categoryId = "DOWNLOAD_ERROR"
    static let destinationKey = "destination"
    static let destinationDownloads = "downloads"
    static let episodeIdKey = "episodeId"

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
    static func notifyIfNeeded(entry: DownloadErrorEntry, settings: AppSettings?) async {
        guard let settings, settings.notifyOnDownloadErrors else { return }

        var status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        if status == .notDetermined {
            status = await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        // Prefer episode title; fall back to feed title before generic "Download failed"
        // so an empty episode title does not hide which podcast failed.
        let episodeTitle = entry.episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedTitle = entry.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !episodeTitle.isEmpty {
            content.title = episodeTitle
        } else if !feedTitle.isEmpty {
            content.title = feedTitle
        } else {
            content.title = String(localized: "Download failed")
        }
        let short = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = short.isEmpty ? String(localized: "Download failed") : String(short.prefix(120))
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            destinationKey: destinationDownloads,
            episodeIdKey: entry.episodeId
        ]

        let id = "download-error.\(entry.id.uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Best-effort; ignore delivery failures in beta.
        }
    }
}
