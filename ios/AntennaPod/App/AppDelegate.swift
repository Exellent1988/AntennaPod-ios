import UIKit

/// Wires `handleEventsForBackgroundURLSession` so background downloads can finish when
/// the system relaunches or wakes the app.
final class AppDelegate: NSObject, UIApplicationDelegate {
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
}
