import Foundation

/// fyyd.de podcast search API client (`/0.2/search/podcast`). No API key required for basic search.
/// Endpoint: `https://api.fyyd.de/0.2/search/podcast?term=&count=`
struct FyydSearchService {
    private static let searchURL = "https://api.fyyd.de/0.2/search/podcast"

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
                return String(localized: "fyyd search failed (HTTP \(code))")
            case .decoding:
                return String(localized: "Could not read fyyd search results")
            case .emptyResponse:
                return String(localized: "Empty response from fyyd")
            }
        }
    }

    func search(term: String) async throws -> [FyydPodcastResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SearchError.invalidQuery
        }

        var components = URLComponents(string: Self.searchURL)!
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "count", value: "25"),
            URLQueryItem(name: "page", value: "0"),
        ]
        guard let url = components.url else {
            throw SearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await AppURLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SearchError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else {
            throw SearchError.emptyResponse
        }

        let decoded: FyydSearchResponse
        do {
            decoded = try JSONDecoder().decode(FyydSearchResponse.self, from: data)
        } catch {
            throw SearchError.decoding
        }

        // Skip entries without a usable feed URL (same as iTunes / Podcast Index).
        return decoded.data.filter { !$0.feedUrl.isEmpty }
    }
}

// MARK: - DTOs

struct FyydSearchResponse: Decodable {
    let status: Int?
    let msg: String?
    let data: [FyydPodcastResult]
}

struct FyydPodcastResult: Identifiable, Hashable, Decodable {
    /// Stable id for list rows (fyyd id when present, else feedUrl).
    var id: String {
        if let fyydId {
            return "fyyd-\(fyydId)"
        }
        return feedUrl
    }

    let fyydId: Int?
    let title: String
    let author: String
    let feedUrl: String
    let imgURL: String?
    let thumbImageURL: String?

    var artworkURL: URL? {
        let raw = imgURL ?? thumbImageURL
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    enum CodingKeys: String, CodingKey {
        case fyydId = "id"
        case title
        case author
        case feedUrl = "xmlURL"
        case imgURL
        case thumbImageURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fyydId = try c.decodeIfPresent(Int.self, forKey: .fyydId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Unknown"
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "Unknown"
        feedUrl = try c.decodeIfPresent(String.self, forKey: .feedUrl) ?? ""
        imgURL = try c.decodeIfPresent(String.self, forKey: .imgURL)
        thumbImageURL = try c.decodeIfPresent(String.self, forKey: .thumbImageURL)
    }
}
