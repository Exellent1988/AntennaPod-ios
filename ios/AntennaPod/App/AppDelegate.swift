import UIKit
import UserNotifications

/// Wires background URLSession completion and local notification taps (new episodes).
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
        Task { @MainActor in
            if destination == NewEpisodeNotificationCoordinator.destinationInbox
                || response.notification.request.identifier.hasPrefix("new-episodes.")
            {
                NewEpisodeNotificationCoordinator.deepLink.openInbox()
            }
            completionHandler()
        }
    }
}
