import Foundation

/// Android Statistics screen pieces: "Include marked as played" (`countAll`), the Years tab and
/// the Downloads tab.
public enum StatisticsParity {
    /// Listening time for one episode. Android with "Include marked as played" off counts only
    /// time actually played (`played_duration`); on, a played episode counts its full duration.
    /// iOS recorded wall time = played duration; without a recording an unfinished episode counts
    /// its position, a played one counts 0 (marked played, nothing recorded) unless included.
    public static func seconds(recordedWall: Double?, isPlayed: Bool, durationSeconds: Double,
                               positionSeconds: Double, includeMarkedPlayed: Bool) -> Double {
        if includeMarkedPlayed {
            return ListeningTimeRule.seconds(recordedWall: recordedWall, isPlayed: isPlayed,
                                             durationSeconds: durationSeconds, positionSeconds: positionSeconds)
        }
        if let recordedWall, recordedWall.isFinite, recordedWall > 0 { return recordedWall }
        if isPlayed { return 0 }
        return positionSeconds.isFinite ? max(0, positionSeconds) : 0
    }

    public struct YearTotal: Equatable, Sendable {
        public var year: Int
        public var seconds: Double
        public var episodes: Int
    }

    /// Android Years tab: listening time per calendar year, newest year first, empty years skipped.
    public static func yearTotals(_ items: [(epochMs: Int64, seconds: Double)], calendar: Calendar) -> [YearTotal] {
        var byYear: [Int: YearTotal] = [:]
        for item in items where item.seconds > 0 {
            let year = calendar.component(.year, from: Date(timeIntervalSince1970: Double(item.epochMs) / 1000))
            var t = byYear[year] ?? YearTotal(year: year, seconds: 0, episodes: 0)
            t.seconds += item.seconds
            t.episodes += 1
            byYear[year] = t
        }
        return byYear.values.sorted { $0.year > $1.year }
    }

    public struct DownloadTotal: Equatable, Sendable {
        public var key: String
        public var title: String
        public var episodes: Int
        public var bytes: Int64
    }

    /// Android Downloads tab: downloaded episodes and size per podcast, largest first.
    public static func downloadTotals(_ items: [(key: String, title: String, bytes: Int64)]) -> [DownloadTotal] {
        var byKey: [String: DownloadTotal] = [:]
        for item in items {
            var t = byKey[item.key] ?? DownloadTotal(key: item.key, title: item.title, episodes: 0, bytes: 0)
            t.episodes += 1
            t.bytes += max(0, item.bytes)
            byKey[item.key] = t
        }
        return byKey.values.sorted { ($0.bytes, $1.title) > ($1.bytes, $0.title) }
    }
}
