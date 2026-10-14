import Foundation
import StoreKit
import UIKit

/// Optional App Store rating prompt after N successful mark-played / finishes (once per install).
///
/// Calls `AppStore.requestReview(in:)` from a UI window scene. iOS may suppress the sheet
/// (system quotas); we still mark "requested" so we never spam. Settings can disable or reset
/// for testing.
@MainActor
enum RatingPromptCoordinator {
    /// Successful mark-played events before the first (and only) request attempt.
    static let threshold = 10

    private enum Keys {
        static let count = "ratingPrompt.successfulMarkPlayedCount"
        static let hasRequested = "ratingPrompt.hasRequestedReview"
    }

    /// How many newly marked-played episodes have been counted this install.
    static var successfulMarkPlayedCount: Int {
        UserDefaults.standard.integer(forKey: Keys.count)
    }

    /// `true` after we already asked the system once (sheet may or may not have appeared).
    static var hasRequestedReview: Bool {
        UserDefaults.standard.bool(forKey: Keys.hasRequested)
    }

    /// Call when an episode transitions to played (manual or playback finished). No-op if already played.
    static func recordSuccessfulMarkPlayed(settings: AppSettings?) {
        guard let settings, settings.askForAppStoreRating else { return }
        guard !hasRequestedReview else { return }

        let next = successfulMarkPlayedCount + 1
        UserDefaults.standard.set(next, forKey: Keys.count)
        guard next >= threshold else { return }

        // Defer slightly so the UI scene is settled after mark-played / continuous-next.
        DispatchQueue.main.async {
            requestReviewIfAppropriate(settings: settings)
        }
    }

    /// Ask StoreKit once. Marks requested even if iOS does not show a sheet.
    static func requestReviewIfAppropriate(settings: AppSettings?) {
        guard let settings, settings.askForAppStoreRating else { return }
        guard !hasRequestedReview else { return }
        guard successfulMarkPlayedCount >= threshold else { return }

        guard let scene = foregroundWindowScene() else {
            // No scene yet — try again next mark-played (do not set hasRequested).
            return
        }

        // Persist before the call so a suppressed sheet still counts as our one attempt.
        UserDefaults.standard.set(true, forKey: Keys.hasRequested)
        AppStore.requestReview(in: scene)
    }

    /// Clears count + requested flag (Settings testing).
    static func resetState() {
        UserDefaults.standard.removeObject(forKey: Keys.count)
        UserDefaults.standard.removeObject(forKey: Keys.hasRequested)
    }

    private static func foregroundWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }
}
