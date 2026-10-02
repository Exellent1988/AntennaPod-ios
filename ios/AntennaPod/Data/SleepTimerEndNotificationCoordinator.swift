import Foundation
import UIKit
import UserNotifications

/// Local UserNotifications (+ foreground haptic) when the sleep timer expires.
/// Reuses the same UNUserNotificationCenter permission path as new-episode / DL / sync alerts.
///
/// **Honesty:** one stable notification id per fire (replaces prior); Settings toggle default on;
/// no push / APNs; denied stays denied (haptic still fires in foreground when toggle is on).
@MainActor
enum SleepTimerEndNotificationCoordinator {
    static let categoryId = "SLEEP_TIMER_END"
    /// Stable id so a later fire replaces the prior banner (no spam stack).
    static let notificationId = "sleep-timer.end"

    /// Which sleep-timer mode fired — drives notification body copy (EN/DE catalog).
    enum Kind {
        case clock
        case endOfEpisode
        case endOfChapter
        case endOfQueue
    }

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

    /// When Settings toggle is on: foreground haptic; local banner if system permission allows.
    static func notifyIfNeeded(kind: Kind, settings: AppSettings?) async {
        guard let settings, settings.notifyOnSleepTimerEnd else { return }

        if UIApplication.shared.applicationState == .active {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }

        var status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        if status == .notDetermined {
            status = await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Sleep timer ended")
        switch kind {
        case .endOfEpisode:
            content.body = String(localized: "End of episode — playback stopped.")
        case .endOfChapter:
            content.body = String(localized: "End of chapter — playback paused.")
        case .endOfQueue:
            content.body = String(localized: "End of queue — playback stopped.")
        case .clock:
            content.body = String(localized: "Playback paused.")
        }
        content.sound = .default
        content.categoryIdentifier = categoryId

        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Best-effort; ignore delivery failures in beta.
        }
    }
}
