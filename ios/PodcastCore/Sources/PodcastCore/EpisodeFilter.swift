import Foundation

/// Per-podcast auto-download filter (Android `FeedFilter`).
///
/// - Include terms: when non-empty, an episode must match at least one.
/// - Exclude terms: an episode matching any is skipped (wins over include).
/// - Terms are whitespace-separated words or `"quoted phrases"`, matched case- and
///   diacritic-insensitively against the episode title (Android matches the title too).
/// - Min / max duration in seconds (0 = no limit). Unknown duration (≤ 0) passes, like Android.
///
/// Android has include *or* exclude plus a minimum duration; iOS allows both lists and a maximum.
public struct EpisodeFilter: Codable, Hashable, Sendable {
    public var includeTerms: String
    public var excludeTerms: String
    public var minimumDurationSeconds: Int
    public var maximumDurationSeconds: Int

    public init(includeTerms: String = "", excludeTerms: String = "",
                minimumDurationSeconds: Int = 0, maximumDurationSeconds: Int = 0) {
        self.includeTerms = includeTerms
        self.excludeTerms = excludeTerms
        self.minimumDurationSeconds = max(0, minimumDurationSeconds)
        self.maximumDurationSeconds = max(0, maximumDurationSeconds)
    }

    public static let none = EpisodeFilter()

    /// `true` when no rule is set (everything passes).
    public var isEmpty: Bool {
        Self.parseTerms(includeTerms).isEmpty && Self.parseTerms(excludeTerms).isEmpty
            && minimumDurationSeconds == 0 && maximumDurationSeconds == 0
    }

    /// Whether an episode may be auto-downloaded.
    public func allows(title: String, durationSeconds: Double) -> Bool {
        let haystack = Self.fold(title)
        let include = Self.parseTerms(includeTerms)
        let exclude = Self.parseTerms(excludeTerms)
        if exclude.contains(where: { haystack.contains($0) }) { return false }
        if !include.isEmpty, !include.contains(where: { haystack.contains($0) }) { return false }
        if durationSeconds.isFinite, durationSeconds > 0 {
            if minimumDurationSeconds > 0, durationSeconds < Double(minimumDurationSeconds) { return false }
            if maximumDurationSeconds > 0, durationSeconds > Double(maximumDurationSeconds) { return false }
        }
        return true
    }

    /// Split into folded terms: words, or text inside double quotes as one phrase.
    public static func parseTerms(_ raw: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var inQuotes = false
        func flush() {
            let t = fold(current.trimmingCharacters(in: .whitespaces))
            if !t.isEmpty, !terms.contains(t) { terms.append(t) }
            current = ""
        }
        for ch in raw {
            if ch == "\"" || ch == "“" || ch == "”" {
                flush()
                inQuotes.toggle()
            } else if !inQuotes, ch.isWhitespace || ch == "," {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return terms
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
