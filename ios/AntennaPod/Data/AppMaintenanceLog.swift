import Foundation
import os

/// Outcome of `PodcastStore.resetAppDataSafely`.
struct AppDataResetReport: Equatable {
    var feedsBefore: Int
    var queueBefore: Int
    var stoppedPlayback = false
    var cancelledDownloads = 0
    var downloadsDrained = true
}

/// Small persistent log for destructive maintenance (Reset app data, re-import). Lines go to the
/// unified log (subsystem de.danoeh.antennapod.ios, category maintenance) and the last 100 are
/// kept in UserDefaults so they survive the reset itself. No URLs, credentials or user data.
enum AppMaintenanceLog {
    static let defaultsKey = "maintenance.log"
    static let maxEntries = 100
    private static let logger = Logger(subsystem: "de.danoeh.antennapod.ios", category: "maintenance")

    static func record(_ message: String, date: Date = Date(), defaults: UserDefaults = .standard) {
        logger.notice("\(message, privacy: .public)")
        let stamp = ISO8601DateFormatter().string(from: date)
        var lines = defaults.stringArray(forKey: defaultsKey) ?? []
        lines.append("\(stamp) \(message)")
        if lines.count > maxEntries { lines.removeFirst(lines.count - maxEntries) }
        defaults.set(lines, forKey: defaultsKey)
    }

    static func entries(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }
}
