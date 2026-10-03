import CryptoKit
import Foundation

/// Podcast Index search API client (`/api/1.0/search/byterm`).
/// Auth: `X-Auth-Date` + `X-Auth-Key` + `Authorization` = sha1(apiKey+apiSecret+unixTime).
/// Keys come from `PodcastIndexKeychain` (user-supplied); never hardcoded.
struct PodcastIndexSearchService {
    private static let searchURL = "https://api.podcastindex.org/api/1.0/search/byterm"
    /// Cap results like iTunes (`limit=25`) / fyyd (`count=25`). Podcast Index `max` defaults higher.
    private static let resultLimit = 25

    enum SearchError: LocalizedError {
        case missingCredentials
        case invalidQuery
        case unauthorized
        case httpStatus(Int)
        case decoding
        case emptyResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return String(localized: "Add your Podcast Index API key and secret in Settings → Discovery")
            case .invalidQuery:
                return String(localized: "Enter a search term")
            case .unauthorized:
                return String(localized: "Podcast Index rejected the API key or secret. Check Settings → Discovery, or register free keys at podcastindex.org.")
            case .httpStatus(let code):
                return String(localized: "Podcast Index search failed (HTTP \(code))")
            case .decoding:
                return String(localized: "Could not read Podcast Index search results")
            case .emptyResponse:
                return String(localized: "Empty response from Podcast Index")
            case .network(let detail):
                return String(localized: "Podcast Index network error: \(detail)")
            }
        }
    }

    func search(term: String) async throws -> [PodcastIndexPodcastResult] {
        guard let apiKey = PodcastIndexKeychain.loadAPIKey(),
              let apiSecret = PodcastIndexKeychain.loadAPISecret(),
              !apiKey.isEmpty,
              !apiSecret.isEmpty
        else {
            throw SearchError.missingCredentials
        }

        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SearchError.invalidQuery
        }

        var components = URLComponents(string: Self.searchURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "max", value: String(Self.resultLimit)),
        ]
        guard let url = components.url else {
            throw SearchError.invalidQuery
        }

        let unixTime = String(Int(Date().timeIntervalSince1970))
        let authHash = Self.sha1Hex(apiKey + apiSecret + unixTime)

        var request = URLRequest(url: url)
        request.setValue(unixTime, forHTTPHeaderField: "X-Auth-Date")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue(authHash, forHTTPHeaderField: "Authorization")
        AppUserAgent.apply(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AppURLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw SearchError.network(urlError.localizedDescription)
        } catch {
            throw SearchError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw SearchError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                throw SearchError.httpStatus(http.statusCode)
            }
        }
        guard !data.isEmpty else {
            throw SearchError.emptyResponse
        }

        let decoded: PodcastIndexSearchResponse
        do {
            decoded = try JSONDecoder().decode(PodcastIndexSearchResponse.self, from: data)
        } catch {
            throw SearchError.decoding
        }

        // Skip entries without a usable feed URL (same as Android / iTunes). Cap client-side too.
        return Array(decoded.feeds.filter { !$0.feedUrl.isEmpty }.prefix(Self.resultLimit))
    }

    /// SHA-1 hex digest per Podcast Index auth docs (and Android `PodcastIndexPodcastSearcher`).
    static func sha1Hex(_ string: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - DTOs

struct PodcastIndexSearchResponse: Decodable {
    let feeds: [PodcastIndexPodcastResult]
}

struct PodcastIndexPodcastResult: Identifiable, Hashable, Decodable {
    var id: String {
        if let feedId {
            return "podcastindex-\(feedId)"
        }
        return feedUrl
    }

    let feedId: Int?
    let title: String
    let author: String
    let feedUrl: String
    let image: String?

    var artworkURL: URL? {
        guard let image, !image.isEmpty else { return nil }
        return URL(string: image)
    }

    enum CodingKeys: String, CodingKey {
        case feedId = "id"
        case title
        case author
        case feedUrl = "url"
        case image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedId = try c.decodeIfPresent(Int.self, forKey: .feedId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? String(localized: "Unknown")
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? String(localized: "Unknown")
        feedUrl = try c.decodeIfPresent(String.self, forKey: .feedUrl) ?? ""
        image = try c.decodeIfPresent(String.self, forKey: .image)
    }
}
