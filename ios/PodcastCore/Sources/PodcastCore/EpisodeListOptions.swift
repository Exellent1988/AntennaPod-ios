import Foundation

/// Android `EpisodeFilter` (filter dialog tokens) + `SortOrder` for episode lists.
/// Tokens come in mutually exclusive pairs (Android `FeedItemFilterGroup`); several pairs AND together.
public enum EpisodeFilterToken: String, CaseIterable, Codable, Sendable, Hashable {
    case unplayed, played
    case paused, notPaused
    case downloaded, notDownloaded
    case queued, notQueued
    case favorite, notFavorite
    case hasMedia, noMedia
    case hasChapters, noChapters

    /// The other half of the pair; selecting one removes it (Android radio-like group).
    public var opposite: EpisodeFilterToken {
        switch self {
        case .unplayed: return .played
        case .played: return .unplayed
        case .paused: return .notPaused
        case .notPaused: return .paused
        case .downloaded: return .notDownloaded
        case .notDownloaded: return .downloaded
        case .queued: return .notQueued
        case .notQueued: return .queued
        case .favorite: return .notFavorite
        case .notFavorite: return .favorite
        case .hasMedia: return .noMedia
        case .noMedia: return .hasMedia
        case .hasChapters: return .noChapters
        case .noChapters: return .hasChapters
        }
    }

    /// Pairs in Android dialog order.
    public static let groups: [(EpisodeFilterToken, EpisodeFilterToken)] = [
        (.unplayed, .played), (.paused, .notPaused), (.downloaded, .notDownloaded),
        (.queued, .notQueued), (.favorite, .notFavorite), (.hasMedia, .noMedia), (.hasChapters, .noChapters),
    ]
}

/// Per-episode facts the filter and sort need (built by the app from store/downloads).
public struct EpisodeListFacts: Sendable, Equatable {
    public var isPlayed: Bool
    public var positionSeconds: Double
    public var isDownloaded: Bool
    public var isQueued: Bool
    public var isFavorite: Bool
    public var hasMedia: Bool
    public var hasChapters: Bool
    public var pubDateEpochMs: Int64?
    public var durationSeconds: Double
    public var title: String
    public var feedTitle: String
    public var sizeBytes: Int64

    public init(isPlayed: Bool = false, positionSeconds: Double = 0, isDownloaded: Bool = false, isQueued: Bool = false,
                isFavorite: Bool = false, hasMedia: Bool = true, hasChapters: Bool = false, pubDateEpochMs: Int64? = nil,
                durationSeconds: Double = 0, title: String = "", feedTitle: String = "", sizeBytes: Int64 = 0) {
        self.isPlayed = isPlayed; self.positionSeconds = positionSeconds; self.isDownloaded = isDownloaded
        self.isQueued = isQueued; self.isFavorite = isFavorite; self.hasMedia = hasMedia; self.hasChapters = hasChapters
        self.pubDateEpochMs = pubDateEpochMs; self.durationSeconds = durationSeconds; self.title = title
        self.feedTitle = feedTitle; self.sizeBytes = sizeBytes
    }

    /// Android `FeedItem.isInProgress`: position > 0 and not played.
    public var isPaused: Bool { !isPlayed && positionSeconds > 0 }
}

public struct EpisodeListFilter: Codable, Equatable, Sendable {
    public var tokens: Set<EpisodeFilterToken>
    public init(_ tokens: Set<EpisodeFilterToken> = []) { self.tokens = tokens }
    public var isEmpty: Bool { tokens.isEmpty }

    public mutating func toggle(_ token: EpisodeFilterToken) {
        if tokens.contains(token) { tokens.remove(token) } else { tokens.remove(token.opposite); tokens.insert(token) }
    }

    public func matches(_ f: EpisodeListFacts) -> Bool {
        tokens.allSatisfy { t in
            switch t {
            case .unplayed: return !f.isPlayed
            case .played: return f.isPlayed
            case .paused: return f.isPaused
            case .notPaused: return !f.isPaused
            case .downloaded: return f.isDownloaded
            case .notDownloaded: return !f.isDownloaded
            case .queued: return f.isQueued
            case .notQueued: return !f.isQueued
            case .favorite: return f.isFavorite
            case .notFavorite: return !f.isFavorite
            case .hasMedia: return f.hasMedia
            case .noMedia: return !f.hasMedia
            case .hasChapters: return f.hasChapters
            case .noChapters: return !f.hasChapters
            }
        }
    }
}

/// Android `SortOrder` (episode subset; random / smart shuffle / filename are not offered).
public enum EpisodeListSortOrder: String, CaseIterable, Codable, Sendable {
    case dateNewOld, dateOldNew
    case durationShortLong, durationLongShort
    case titleAZ, titleZA
    case sizeSmallLarge, sizeLargeSmall
    case feedTitleAZ, feedTitleZA

    /// Stable sort; unknown (0 / nil / empty) values go last in both directions, ties keep input order.
    public func sorted<T>(_ items: [T], facts: (T) -> EpisodeListFacts) -> [T] {
        let keyed = items.enumerated().map { ($0.offset, $0.element, facts($0.element)) }
        return keyed.sorted { a, b in
            switch compare(a.2, b.2) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.0 < b.0
            }
        }.map(\.1)
    }

    private func compare(_ a: EpisodeListFacts, _ b: EpisodeListFacts) -> ComparisonResult {
        func num<V: Comparable>(_ x: V?, _ y: V?, ascending: Bool) -> ComparisonResult {
            switch (x, y) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            case let (x?, y?):
                if x == y { return .orderedSame }
                return (x < y) == ascending ? .orderedAscending : .orderedDescending
            }
        }
        func str(_ x: String, _ y: String, ascending: Bool) -> ComparisonResult {
            let xt = x.trimmingCharacters(in: .whitespaces), yt = y.trimmingCharacters(in: .whitespaces)
            return num(xt.isEmpty ? nil : xt.lowercased(), yt.isEmpty ? nil : yt.lowercased(), ascending: ascending)
        }
        let dur: (EpisodeListFacts) -> Double? = { $0.durationSeconds > 0 ? $0.durationSeconds : nil }
        let size: (EpisodeListFacts) -> Int64? = { $0.sizeBytes > 0 ? $0.sizeBytes : nil }
        switch self {
        case .dateNewOld: return num(a.pubDateEpochMs, b.pubDateEpochMs, ascending: false)
        case .dateOldNew: return num(a.pubDateEpochMs, b.pubDateEpochMs, ascending: true)
        case .durationShortLong: return num(dur(a), dur(b), ascending: true)
        case .durationLongShort: return num(dur(a), dur(b), ascending: false)
        case .titleAZ: return str(a.title, b.title, ascending: true)
        case .titleZA: return str(a.title, b.title, ascending: false)
        case .sizeSmallLarge: return num(size(a), size(b), ascending: true)
        case .sizeLargeSmall: return num(size(a), size(b), ascending: false)
        case .feedTitleAZ: return str(a.feedTitle, b.feedTitle, ascending: true)
        case .feedTitleZA: return str(a.feedTitle, b.feedTitle, ascending: false)
        }
    }
}

/// Filter + optional sort for one screen (or one feed). `sort == nil` keeps the screen's own sort.
public struct EpisodeListOptions: Codable, Equatable, Sendable {
    public var filter: EpisodeListFilter
    public var sort: EpisodeListSortOrder?
    public init(filter: EpisodeListFilter = .init(), sort: EpisodeListSortOrder? = nil) { self.filter = filter; self.sort = sort }
    public var isDefault: Bool { filter.isEmpty && sort == nil }

    public func apply<T>(_ items: [T], facts: (T) -> EpisodeListFacts) -> [T] {
        if isDefault { return items }
        var cache: [Int: EpisodeListFacts] = [:]
        var indexed = Array(items.enumerated())
        for (i, item) in indexed { cache[i] = facts(item) }
        if !filter.isEmpty { indexed = indexed.filter { filter.matches(cache[$0.offset]!) } }
        if let sort { indexed = sort.sorted(indexed) { cache[$0.offset]! } }
        return indexed.map(\.element)
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> EpisodeListOptions {
        data.flatMap { try? JSONDecoder().decode(EpisodeListOptions.self, from: $0) } ?? .init()
    }
}
