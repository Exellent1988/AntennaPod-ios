import UIKit
import UserNotifications

/// Wires background URLSession completion and local notification taps (new episodes / DL error·complete / sync errors / sleep timer end).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NewEpisodeNotificationCoordinator.configureIfNeeded(delegate: self)
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadService.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            DownloadService.registerBackgroundCompletionHandler(completionHandler)
        }
    }

    // Show banner while app is foreground (local new-episode alerts).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    // Best-effort deep link: open Inbox tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let destination = info[NewEpisodeNotificationCoordinator.destinationKey] as? String
            ?? info[DownloadErrorNotificationCoordinator.destinationKey] as? String
            ?? info[DownloadCompleteNotificationCoordinator.destinationKey] as? String
            ?? info[SyncErrorNotificationCoordinator.destinationKey] as? String
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if destination == SyncErrorNotificationCoordinator.destinationSettingsSync
                || identifier.hasPrefix("sync-error.")
            {
                NewEpisodeNotificationCoordinator.deepLink.openSettingsSync()
            } else if destination == DownloadErrorNotificationCoordinator.destinationDownloads
                || destination == DownloadCompleteNotificationCoordinator.destinationDownloads
                || identifier.hasPrefix("download-error.")
                || identifier.hasPrefix("download-complete.")
            {
                NewEpisodeNotificationCoordinator.deepLink.openDownloads()
            } else if destination == NewEpisodeNotificationCoordinator.destinationInbox
                || identifier.hasPrefix("new-episodes.")
            {
                NewEpisodeNotificationCoordinator.deepLink.openInbox()
            }
            completionHandler()
        }
    }
}
