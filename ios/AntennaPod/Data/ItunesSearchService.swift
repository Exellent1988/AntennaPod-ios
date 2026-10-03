import Foundation

/// Apple iTunes Search API client (podcasts). No API key required.
/// Mirrors Android `ItunesPodcastSearcher` (`https://itunes.apple.com/search?media=podcast&term=`).
struct ItunesSearchService {
    private static let searchURL = "https://itunes.apple.com/search"

    enum SearchError: LocalizedError {
        case invalidQuery
        case httpStatus(Int)
        case decoding
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidQuery:
                return String(localized: "Enter a search term")
            case .httpStatus(let code):
                return String(localized: "iTunes search failed (HTTP \(code))")
            case .decoding:
                return String(localized: "Could not read iTunes search results")
            case .emptyResponse:
                return String(localized: "Empty response from iTunes")
            }
        }
    }

    func search(term: String) async throws -> [ItunesPodcastResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SearchError.invalidQuery
        }

        var components = URLComponents(string: Self.searchURL)!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = components.url else {
            throw SearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        request.timeoutInterval = 20

        let (data, response) = try await AppURLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SearchError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else {
            throw SearchError.emptyResponse
        }

        let decoded: ItunesSearchResponse
        do {
            decoded = try JSONDecoder().decode(ItunesSearchResponse.self, from: data)
        } catch {
            throw SearchError.decoding
        }

        // Skip entries without a usable feed URL (same as Android).
        return decoded.results.filter { !$0.feedUrl.isEmpty }
    }
}

// MARK: - DTOs

struct ItunesSearchResponse: Decodable {
    let resultCount: Int?
    let results: [ItunesPodcastResult]
}

struct ItunesPodcastResult: Identifiable, Hashable, Decodable {
    /// Stable id for list rows (collectionId when present, else feedUrl).
    var id: String {
        if let collectionId {
            return "itunes-\(collectionId)"
        }
        return feedUrl
    }

    let collectionId: Int?
    let collectionName: String
    let artistName: String
    let feedUrl: String
    let artworkUrl100: String?
    let artworkUrl600: String?

    var title: String { collectionName }
    var author: String { artistName }
    var artworkURL: URL? {
        let raw = artworkUrl600 ?? artworkUrl100
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    enum CodingKeys: String, CodingKey {
        case collectionId
        case collectionName
        case artistName
        case feedUrl
        case artworkUrl100
        case artworkUrl600
    }

    init(
        collectionId: Int?,
        collectionName: String,
        artistName: String,
        feedUrl: String,
        artworkUrl100: String?,
        artworkUrl600: String?
    ) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.artistName = artistName
        self.feedUrl = feedUrl
        self.artworkUrl100 = artworkUrl100
        self.artworkUrl600 = artworkUrl600
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectionId = try c.decodeIfPresent(Int.self, forKey: .collectionId)
        collectionName = try c.decodeIfPresent(String.self, forKey: .collectionName) ?? "Unknown"
        artistName = try c.decodeIfPresent(String.self, forKey: .artistName) ?? "Unknown"
        feedUrl = try c.decodeIfPresent(String.self, forKey: .feedUrl) ?? ""
        artworkUrl100 = try c.decodeIfPresent(String.self, forKey: .artworkUrl100)
        artworkUrl600 = try c.decodeIfPresent(String.self, forKey: .artworkUrl600)
    }
}
