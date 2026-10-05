import Foundation

/// Plain-text export of the **full** subscriptions library (`PodcastStore.feeds`).
/// Stable order: display title A–Z (`localizedCaseInsensitiveCompare`; empty last; id tiebreak).
/// Does **not** follow UI `subscriptionsSort`, pin partition, or search / category / language / tag / Pinned-chip filters.
/// One line per feed: `1. Display title — feed URL` (1-based index; local-folder URLs included honestly).
/// Local plain text only — not OPML, not HTML export, not gpodder, not a deep link.
enum SubscriptionsExport {
    /// Body only (no “Subscriptions” header). Empty when `feeds` is empty.
    static func plainText(
        feeds: [PodcastFeed],
        displayTitleFor: (PodcastFeed) -> String
    ) -> String {
        guard !feeds.isEmpty else { return "" }
        let ordered = sortedForExport(feeds, displayTitleFor: displayTitleFor)
        return ordered.enumerated().map { index, feed in
            line(index: index + 1, title: displayTitleFor(feed), feedUrl: feed.feedUrl)
        }.joined(separator: "\n")
    }

    /// System share payload: localized “Subscriptions” header + blank line + body (same body as `plainText`).
    /// Empty when `feeds` is empty.
    static func shareText(
        feeds: [PodcastFeed],
        displayTitleFor: (PodcastFeed) -> String
    ) -> String {
        let body = plainText(feeds: feeds, displayTitleFor: displayTitleFor)
        guard !body.isEmpty else { return "" }
        let header = String(localized: "Subscriptions")
        return "\(header)\n\n\(body)"
    }

    /// Display title A–Z; empty titles last; UUID string tiebreak. Independent of UI sort / pin.
    static func sortedForExport(
        _ feeds: [PodcastFeed],
        displayTitleFor: (PodcastFeed) -> String
    ) -> [PodcastFeed] {
        feeds.sorted { lhs, rhs in
            let lt = displayTitleFor(lhs).trimmingCharacters(in: .whitespacesAndNewlines)
            let rt = displayTitleFor(rhs).trimmingCharacters(in: .whitespacesAndNewlines)
            switch (lt.isEmpty, rt.isEmpty) {
            case (false, true):
                return true
            case (true, false):
                return false
            case (true, true):
                return lhs.id.uuidString < rhs.id.uuidString
            case (false, false):
                let cmp = lt.localizedCaseInsensitiveCompare(rt)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    private static func line(index: Int, title: String, feedUrl: String) -> String {
        var display = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if display.isEmpty {
            display = String(localized: "Podcast")
        }
        let url = FeedURLNormalization.strippingCredentials(feedUrl)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(index). \(display) — \(url)"
    }
}
