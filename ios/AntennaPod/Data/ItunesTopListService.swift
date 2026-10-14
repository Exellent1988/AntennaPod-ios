import Foundation

/// Apple iTunes RSS top podcasts charts (no API key).
/// Mirrors Android `ItunesTopListLoader`
/// (`https://itunes.apple.com/{country}/rss/toppodcasts/limit={N}/explicit={true|false}/json`).
/// `N` comes from the caller (full Discover → `AppSettings.discoverChartsLimit`; Home preview →
/// `homeDiscoverPreviewLimit`); clamped to `appleChartsLimitRange` (1…200). Default parameter
/// fallback remains `defaultLimit` (25). Chart entries expose a collection id; real RSS `feedUrl`
/// comes from a batch `lookup`.
struct ItunesTopListService {
    static let defaultLimit = 25
    /// Sane Apple iTunes RSS `limit=` clamp (inclusive). Presets stay well inside this range.
    static let appleChartsLimitRange = 1...200

    enum TopListError: LocalizedError {
        case invalidCountry
        case httpStatus(Int)
        case countryUnavailable
        case decoding
        case emptyResponse
        case lookupFailed

        var errorDescription: String? {
            switch self {
            case .invalidCountry:
                return String(localized: "Invalid country code for charts")
            case .httpStatus(let code):
                return String(localized: "iTunes charts failed (HTTP \(code))")
            case .countryUnavailable:
                return String(localized: "iTunes does not have chart data for the selected country")
            case .decoding:
                return String(localized: "Could not read iTunes chart results")
            case .emptyResponse:
                return String(localized: "Empty response from iTunes charts")
            case .lookupFailed:
                return String(localized: "Could not resolve podcast feed URLs from iTunes")
            }
        }
    }

    /// Fetch top podcasts for `country` (ISO 3166-1 alpha-2, e.g. `de`, `us`).
    /// Resolves each entry’s RSS `feedUrl` via a single batch lookup when possible.
    /// - Parameter includeExplicit: when `false`, requests `explicit=false` (parental controls).
    func loadTopList(
        country: String,
        limit: Int = Self.defaultLimit,
        includeExplicit: Bool = true
    ) async throws -> [ItunesPodcastResult] {
        let code = Self.normalizedCountryCode(country)
        guard !code.isEmpty else { throw TopListError.invalidCountry }

        let entries = try await fetchChartEntries(country: code, limit: limit, includeExplicit: includeExplicit)
        guard !entries.isEmpty else { return [] }

        let feedByCollectionId = try await lookupFeedUrls(collectionIds: entries.map(\.collectionId))

        var results: [ItunesPodcastResult] = []
        results.reserveCapacity(min(limit, entries.count))
        for entry in entries {
            guard results.count < limit else { break }
            let feedUrl = feedByCollectionId[entry.collectionId] ?? ""
            // Skip rows we cannot subscribe to (no resolved feed URL).
            guard !feedUrl.isEmpty else { continue }
            results.append(
                ItunesPodcastResult(
                    collectionId: entry.collectionId,
                    collectionName: entry.title,
                    artistName: entry.artist,
                    feedUrl: feedUrl,
                    artworkUrl100: entry.artworkUrl,
                    artworkUrl600: entry.artworkUrl
                )
            )
        }
        return results
    }

    /// Device region if it looks like ISO alpha-2; otherwise `de` (task default).
    static func defaultCountryCode() -> String {
        if let region = Locale.current.region?.identifier {
            let code = region.lowercased()
            if code.count == 2, code.allSatisfy(\.isLetter) {
                return code
            }
        }
        // Older Locale API fallback
        let legacy = Locale.current.regionCode?.lowercased() ?? ""
        if legacy.count == 2, legacy.allSatisfy(\.isLetter) {
            return legacy
        }
        return "de"
    }

    static func normalizedCountryCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 2, trimmed.allSatisfy(\.isLetter) else { return "" }
        return trimmed
    }

    // MARK: - Charts RSS

    private func fetchChartEntries(country: String, limit: Int = Self.defaultLimit, includeExplicit: Bool = true) async throws -> [ChartEntry] {
        // Clamp requested limit into a sane Apple RSS range; put that N into the URL.
        let clamped = min(max(limit, Self.appleChartsLimitRange.lowerBound), Self.appleChartsLimitRange.upperBound)
        // Match Android URL shape; parental controls may request explicit=false.
        let explicitFlag = includeExplicit ? "true" : "false"
        let urlString =
            "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=\(clamped)/explicit=\(explicitFlag)/json"
        guard let url = URL(string: urlString) else {
            throw TopListError.invalidCountry
        }

        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        request.timeoutInterval = 25

        let (data, response) = try await AppURLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 400 {
                throw TopListError.countryUnavailable
            }
            if !(200...299).contains(http.statusCode) {
                throw TopListError.httpStatus(http.statusCode)
            }
        }
        guard !data.isEmpty else {
            throw TopListError.emptyResponse
        }

        let decoded: ItunesTopListRSSResponse
        do {
            decoded = try JSONDecoder().decode(ItunesTopListRSSResponse.self, from: data)
        } catch {
            throw TopListError.decoding
        }

        return decoded.feed.entries
    }

    // MARK: - Lookup

    private func lookupFeedUrls(collectionIds: [Int]) async throws -> [Int: String] {
        let unique = Array(Set(collectionIds)).sorted()
        guard !unique.isEmpty else { return [:] }

        // Apple allows comma-separated ids in one lookup call.
        var map: [Int: String] = [:]
        let chunkSize = 25
        var start = 0
        while start < unique.count {
            let end = min(start + chunkSize, unique.count)
            let chunk = Array(unique[start..<end])
            let partial = try await lookupChunk(ids: chunk)
            for (id, feed) in partial {
                map[id] = feed
            }
            start = end
        }
        return map
    }

    private func lookupChunk(ids: [Int]) async throws -> [Int: String] {
        let idList = ids.map(String.init).joined(separator: ",")
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "id", value: idList)]
        guard let url = components.url else {
            throw TopListError.lookupFailed
        }

        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        request.timeoutInterval = 25

        let (data, response) = try await AppURLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TopListError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else {
            throw TopListError.emptyResponse
        }

        let decoded: ItunesSearchResponse
        do {
            decoded = try JSONDecoder().decode(ItunesSearchResponse.self, from: data)
        } catch {
            throw TopListError.lookupFailed
        }

        var map: [Int: String] = [:]
        for result in decoded.results {
            guard let collectionId = result.collectionId, !result.feedUrl.isEmpty else { continue }
            map[collectionId] = result.feedUrl
        }
        return map
    }
}

// MARK: - Chart RSS DTOs

private struct ItunesTopListRSSResponse: Decodable {
    let feed: ItunesTopListFeed
}

private struct ItunesTopListFeed: Decodable {
    let entries: [ChartEntry]

    enum CodingKeys: String, CodingKey {
        case entry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? c.decode([ChartEntry].self, forKey: .entry) {
            entries = many
        } else if let one = try? c.decode(ChartEntry.self, forKey: .entry) {
            entries = [one]
        } else {
            entries = []
        }
    }
}

private struct ChartEntry: Decodable {
    let collectionId: Int
    let title: String
    let artist: String
    let artworkUrl: String?

    enum CodingKeys: String, CodingKey {
        case imName = "im:name"
        case imImage = "im:image"
        case imArtist = "im:artist"
        case id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let name = try? c.decode(LabeledValue.self, forKey: .imName) {
            title = name.label
        } else {
            title = String(localized: "Unknown")
        }

        if let artistObj = try? c.decode(LabeledValue.self, forKey: .imArtist) {
            artist = artistObj.label
        } else {
            artist = String(localized: "Unknown")
        }

        let idObj = try c.decode(ChartId.self, forKey: .id)
        collectionId = idObj.collectionId

        artworkUrl = Self.pickArtwork(from: c)
    }

    private static func pickArtwork(from c: KeyedDecodingContainer<CodingKeys>) -> String? {
        guard let images = try? c.decode([ChartImage].self, forKey: .imImage) else { return nil }
        // Prefer ≥100px (same idea as Android), else largest.
        let sorted = images.sorted { ($0.height ?? 0) < ($1.height ?? 0) }
        if let good = sorted.last(where: { ($0.height ?? 0) >= 100 }) {
            return good.label
        }
        return sorted.last?.label
    }
}

private struct LabeledValue: Decodable {
    let label: String
}

private struct ChartId: Decodable {
    let collectionId: Int

    enum CodingKeys: String, CodingKey {
        case attributes
    }

    enum AttrKeys: String, CodingKey {
        case imId = "im:id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let attrs = try c.nestedContainer(keyedBy: AttrKeys.self, forKey: .attributes)
        let raw = try attrs.decode(String.self, forKey: .imId)
        collectionId = Int(raw) ?? 0
    }
}

private struct ChartImage: Decodable {
    let label: String
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case label
        case attributes
    }

    enum AttrKeys: String, CodingKey {
        case height
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        if let attrs = try? c.nestedContainer(keyedBy: AttrKeys.self, forKey: .attributes),
           let heightStr = try? attrs.decode(String.self, forKey: .height) {
            height = Int(heightStr)
        } else {
            height = nil
        }
    }
}
