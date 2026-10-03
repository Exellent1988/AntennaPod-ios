import Foundation

/// Parses Podcast Index chapters JSON (`podcast:chapters` remote file).
/// Shape: `{ "chapters": [ { "startTime": <seconds>, "title", "url", "img" } ] }`
enum PodcastIndexChapterParser {
    static func parse(jsonData: Data) -> [PodcastChapter]? {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let array = root["chapters"] as? [[String: Any]] else {
            return nil
        }
        var chapters: [PodcastChapter] = []
        for obj in array {
            let start: Double
            if let n = obj["startTime"] as? Double {
                start = n
            } else if let n = obj["startTime"] as? Int {
                start = Double(n)
            } else if let s = obj["startTime"] as? String, let n = ChapterTimeParsing.seconds(from: s) {
                start = n
            } else {
                start = 0
            }
            let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let href = obj["url"] as? String
            let img = obj["img"] as? String ?? obj["image"] as? String
            chapters.append(
                PodcastChapter(
                    title: (title?.isEmpty == false) ? title! : String(localized: "Chapter"),
                    startTimeSeconds: start,
                    href: href,
                    imageUrl: img
                )
            )
        }
        return chapters.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
    }

    static func fetch(urlString: String) async throws -> [PodcastChapter] {
        guard let url = URL(string: urlString) else {
            throw FeedParsingError.message("Invalid chapters URL")
        }
        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        let (data, response) = try await AppURLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FeedParsingError.message("Chapters HTTP \(http.statusCode)")
        }
        guard let chapters = parse(jsonData: data) else {
            throw FeedParsingError.message("Invalid chapters JSON")
        }
        return chapters
    }
}
