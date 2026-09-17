import Foundation

struct FeedRepository {
    func fetchAndParse(feedUrl: String) async throws -> PodcastFeed {
        guard let url = URL(string: feedUrl) else {
            throw FeedParsingError.message("Invalid feed URL")
        }
        var request = URLRequest(url: url)
        request.setValue("AntennaPod-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FeedParsingError.message("HTTP \(http.statusCode)")
        }
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw FeedParsingError.emptyResponse
        }
        var feed = try FeedParsing.parse(xml: xml)
        feed.feedUrl = feedUrl
        return feed
    }
}
