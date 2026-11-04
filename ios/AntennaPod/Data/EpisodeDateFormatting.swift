import Foundation

/// AntennaPod-like episode list publish-date captions (calendar-day buckets).
///
/// - Today / Yesterday / N days ago for the last 7 calendar days (locale via `RelativeDateTimeFormatter`)
/// - Short absolute medium date for older (or future) publish times
///
/// Used by `EpisodeRow` for `pubDateEpochMs` only — History / Favorites / Archived
/// `dateOverride` keeps SwiftUI live `.relative` (hours matter there).
enum EpisodeDateFormatting {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Max inclusive calendar-day distance that still uses a relative caption.
    static let relativeDayLimit = 7

    /// List caption for an episode publish date (or any day-granularity timestamp).
    static func listCaption(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let dayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: dayStart, to: todayStart).day ?? Int.max

        guard (0...relativeDayLimit).contains(days) else {
            // Older than a week, or future feed dates — keep medium absolute (prior EpisodeRow `.date` style).
            return absolute.string(from: date)
        }

        // Day-component strings so "Today" / "Yesterday" / "N days ago" match calendar buckets
        // (not wall-clock hour drift from `localizedString(for:relativeTo:)`).
        let raw = relative.localizedString(from: DateComponents(day: -days))
        return sentenceCased(raw)
    }

    private static func sentenceCased(_ string: String) -> String {
        guard let first = string.first else { return string }
        return String(first).uppercased() + string.dropFirst()
    }
}
