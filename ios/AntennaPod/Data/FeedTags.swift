import Foundation

/// Helpers for subscription tags / folders (simple string labels per feed).
enum FeedTags {
    /// Trim, collapse internal whitespace, reject empty. Case preserved for display; equality is case-insensitive.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Case-insensitive equality for tag names.
    static func equal(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Sorted unique display names (case-insensitive dedupe keeps first-seen casing).
    static func uniqueSorted(_ tags: [String]) -> [String] {
        var seen: [String] = []
        for tag in tags {
            guard let n = normalize(tag) else { continue }
            if !seen.contains(where: { equal($0, n) }) {
                seen.append(n)
            }
        }
        return seen.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

/// Filter / grouping selection on the Subscriptions list.
enum SubscriptionTagFilter: Hashable, Identifiable {
    case all
    case pinned
    case tag(String)
    case untagged

    var id: String {
        switch self {
        case .all: return "__all__"
        case .pinned: return "__pinned__"
        case .untagged: return "__untagged__"
        case .tag(let name): return "tag:\(name.lowercased())"
        }
    }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .pinned: return String(localized: "Pinned")
        case .untagged: return String(localized: "Untagged")
        case .tag(let name): return name
        }
    }
}


/// Category chip selection on the Subscriptions list (feed `itunes:category` text only — never invent).
enum SubscriptionCategoryFilter: Hashable, Identifiable {
    case all
    case category(String)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .category(let name): return "cat:\(name.lowercased())"
        }
    }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .category(let name): return name
        }
    }

    /// Persistable raw value: empty = All; otherwise the category display name.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .category(let name): return name
        }
    }

    static func fromStorage(_ raw: String?) -> SubscriptionCategoryFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .all : .category(trimmed)
    }

    /// Case-insensitive match against a feed's `displayCategories` (empty categories never match a specific chip).
    func matches(_ feed: PodcastFeed) -> Bool {
        switch self {
        case .all:
            return true
        case .category(let name):
            return feed.displayCategories.contains { FeedTags.equal($0, name) }
        }
    }
}


/// Language chip selection on the Subscriptions list (feed-provided language codes only — never invent).
/// Storage uses the raw BCP-47 / ISO code from the feed; chip labels use localized display names.
enum SubscriptionLanguageFilter: Hashable, Identifiable {
    case all
    case language(String)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .language(let code): return "lang:\(code.lowercased())"
        }
    }

    /// Chip title: localized name when Locale knows the code; otherwise the raw code.
    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .language(let code): return FeedLanguageFormatting.displayName(for: code)
        }
    }

    /// Persistable raw value: empty = All; otherwise the feed language code.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .language(let code): return code
        }
    }

    static func fromStorage(_ raw: String?) -> SubscriptionLanguageFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .all : .language(trimmed)
    }

    /// Case-insensitive match against a feed's `languageCode` (empty language never matches a specific chip).
    func matches(_ feed: PodcastFeed) -> Bool {
        switch self {
        case .all:
            return true
        case .language(let code):
            guard let feedCode = feed.languageCode else { return false }
            return FeedTags.equal(feedCode, code)
        }
    }
}
