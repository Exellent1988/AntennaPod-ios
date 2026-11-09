import Foundation

/// Data for the Android-style Statistics charts (pie per podcast, bars per year / month).
public enum StatisticsChartData {
    public struct Slice: Equatable, Sendable {
        public var label: String
        public var seconds: Double
        public var isOther: Bool
    }

    /// Pie slices: the largest `maxSlices - 1` podcasts, the rest merged into one "Other" slice
    /// (Android shows every podcast; we cap so labels stay legible). Zero values dropped.
    public static func pieSlices(_ items: [(label: String, seconds: Double)], maxSlices: Int = 6, otherLabel: String) -> [Slice] {
        let positive = items.filter { $0.seconds > 0 }.sorted { $0.seconds > $1.seconds }
        guard positive.count > maxSlices else { return positive.map { Slice(label: $0.label, seconds: $0.seconds, isOther: false) } }
        let head = positive.prefix(max(1, maxSlices - 1)).map { Slice(label: $0.label, seconds: $0.seconds, isOther: false) }
        let rest = positive.dropFirst(head.count).reduce(0) { $0 + $1.seconds }
        return head + [Slice(label: otherLabel, seconds: rest, isOther: true)]
    }

    /// Listening seconds for each month (index 0 = January) of `year`.
    public static func monthTotals(_ items: [(epochMs: Int64, seconds: Double)], year: Int, calendar: Calendar) -> [Double] {
        var months = Array(repeating: 0.0, count: 12)
        for item in items where item.seconds > 0 {
            let c = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(item.epochMs) / 1000))
            guard c.year == year, let m = c.month, (1...12).contains(m) else { continue }
            months[m - 1] += item.seconds
        }
        return months
    }
}
