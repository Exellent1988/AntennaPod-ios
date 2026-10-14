import Foundation
import UserNotifications

/// Local UserNotifications for download **success** (optional; default off).
/// Reuses the same UNUserNotificationCenter permission path as new-episode / DL-error alerts.
/// **No push / APNs.** Cancelled and failed downloads are not notified here (errors keep their own toggle).
@MainActor
enum DownloadCompleteNotificationCoordinator {
    static let categoryId = "DOWNLOAD_COMPLETE"
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

    /// When Settings toggle is on and system permission allows, post one local banner per episode.
    /// Stable id `download-complete.<episodeId>` replaces a prior success banner for the same episode
    /// (dedupe / no spam stack when the same media finishes again).
    static func notifyIfNeeded(
        episode: PodcastEpisode,
        feedTitle: String?,
        settings: AppSettings?
    ) async {
        guard let settings, settings.notifyOnDownloadComplete else { return }

        var status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        if status == .notDetermined {
            status = await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        // Prefer episode title; fall back to feed title before generic "Download complete"
        // so an empty episode title still names the podcast. Body stays feed when episode
        // title is present; otherwise "Download complete" (avoid duplicating the title).
        let episodeTitle = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let feed = (feedTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !episodeTitle.isEmpty {
            content.title = episodeTitle
            content.body = feed.isEmpty ? String(localized: "Download complete") : feed
        } else if !feed.isEmpty {
            content.title = feed
            content.body = String(localized: "Download complete")
        } else {
            content.title = String(localized: "Download complete")
            content.body = String(localized: "Download complete")
        }
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            destinationKey: destinationDownloads,
            episodeIdKey: episode.id
        ]

        let id = "download-complete.\(episode.id)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Best-effort; ignore delivery failures in beta.
        }
    }
}
