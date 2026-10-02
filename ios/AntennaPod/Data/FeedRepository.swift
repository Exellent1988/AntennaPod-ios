import Foundation

/// Network fetch + parse for RSS/Atom podcast feeds (Preview + Subscribe).
/// Errors are localized and distinguish invalid URL / timeout / network / HTTP / not-a-feed.
struct FeedRepository {
    private static let timeoutSeconds: TimeInterval = 25

    enum FetchError: LocalizedError {
        case invalidURL
        case timeout
        case network(String)
        case httpStatus(Int)
        case emptyResponse
        case notAFeed
        case message(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String(localized: "Enter a valid http(s) feed URL")
            case .timeout:
                return String(localized: "Feed request timed out. Check the URL or try again.")
            case .network(let detail):
                return String(localized: "Could not reach the feed: \(detail)")
            case .httpStatus(let code):
                return String(localized: "Feed server returned HTTP \(code)")
            case .emptyResponse:
                return String(localized: "The feed URL returned empty or unreadable content.")
            case .notAFeed:
                return String(localized: "This URL does not look like an RSS or Atom podcast feed.")
            case .message(let text):
                return text
            }
        }
    }

    func fetchAndParse(feedUrl: String) async throws -> PodcastFeed {
        let resolved: String
        switch FeedURLNormalization.normalize(feedUrl) {
        case .ok(let url):
            resolved = url
        case .empty, .invalid:
            throw FetchError.invalidURL
        }

        guard let url = URL(string: resolved) else {
            throw FetchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("AntennaPod-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeoutSeconds

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw FetchError.timeout
            }
            throw FetchError.network(urlError.localizedDescription)
        } catch {
            throw FetchError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }

        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw FetchError.emptyResponse
        }

        do {
            var feed = try FeedParsing.parse(xml: xml)
            feed.feedUrl = resolved
            return feed
        } catch FeedParsingError.emptyResponse {
            throw FetchError.emptyResponse
        } catch FeedParsingError.unsupported {
            throw FetchError.notAFeed
        } catch FeedParsingError.message {
            throw FetchError.notAFeed
        } catch {
            throw FetchError.notAFeed
        }
    }
}
