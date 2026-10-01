import Foundation

/// AntennaPod-style HTML export lite for subscriptions (self-contained list).
/// Distinct from OPML and the iOS JSON ZIP backup.
enum HtmlExportWriter {
    private static let documentTitle = "AntennaPod Subscriptions"

    /// Build a simple self-contained HTML document: title, feed URL links, optional episode count.
    static func writeDocument(feeds: [PodcastFeed], includeEpisodeCount: Bool = true) -> String {
        let sorted = feeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        var body = ""
        body += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        body += "<!DOCTYPE html>\n"
        body += "<html lang=\"en\">\n"
        body += "<head>\n"
        body += "  <meta charset=\"UTF-8\" />\n"
        body += "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n"
        body += "  <title>\(escape(documentTitle))</title>\n"
        body += "  <style>\n"
        body += css
        body += "  </style>\n"
        body += "</head>\n"
        body += "<body>\n"
        body += "  <header>\n"
        body += "    <h1>\(escape(documentTitle))</h1>\n"
        body += "    <p class=\"meta\">\(sorted.count) subscription\(sorted.count == 1 ? "" : "s")"
        body += " · exported \(escape(displayDate(Date())))</p>\n"
        body += "  </header>\n"
        body += "  <ul class=\"feeds\">\n"
        for feed in sorted {
            guard !feed.feedUrl.isEmpty else { continue }
            body += feedItemHTML(feed: feed, includeEpisodeCount: includeEpisodeCount)
        }
        body += "  </ul>\n"
        body += "  <footer>\n"
        body += "    <p>Exported from AntennaPod iOS · "
        body += "<a href=\"https://antennapod.org\">antennapod.org</a></p>\n"
        body += "  </footer>\n"
        body += "</body>\n"
        body += "</html>\n"
        return body
    }

    /// Write HTML to a temporary file suitable for the share sheet.
    static func writeTemporaryFile(feeds: [PodcastFeed], includeEpisodeCount: Bool = true) throws -> URL {
        let html = writeDocument(feeds: feeds, includeEpisodeCount: includeEpisodeCount)
        let dir = FileManager.default.temporaryDirectory
        let name = "AntennaPod-subscriptions-\(fileStamp()).html"
        let url = dir.appendingPathComponent(name)
        guard let data = html.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func feedItemHTML(feed: PodcastFeed, includeEpisodeCount: Bool) -> String {
        let titleHTML: String
        if let site = feed.siteLink, !site.isEmpty {
            titleHTML = "<a class=\"title\" href=\"\(escapeAttr(site))\">\(escape(feed.title))</a>"
        } else {
            titleHTML = "<span class=\"title\">\(escape(feed.title))</span>"
        }

        var metaParts: [String] = []
        metaParts.append(
            "<a class=\"feed-url\" href=\"\(escapeAttr(feed.feedUrl))\">\(escape(feed.feedUrl))</a>"
        )
        if includeEpisodeCount {
            let n = feed.episodes.count
            metaParts.append("\(n) episode\(n == 1 ? "" : "s")")
        }

        var item = "    <li>\n"
        item += "      <div class=\"card\">\n"
        item += "        <p>\(titleHTML)</p>\n"
        item += "        <p class=\"meta\">\(metaParts.joined(separator: " · "))</p>\n"
        item += "      </div>\n"
        item += "    </li>\n"
        return item
    }

    private static let css = """
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              background: #0d8eff;
              background-image: linear-gradient(180deg, #0f9cff, #0682ff);
              color: #222;
              padding: 16px;
              min-height: 100%;
              text-align: center;
            }
            header { margin: 24px 0 16px; color: #fff; }
            h1 { font-weight: 400; font-size: 1.6rem; margin-bottom: 6px; }
            header .meta, footer p { color: rgba(255,255,255,0.9); font-size: 0.9rem; }
            ul.feeds { list-style: none; max-width: 640px; margin: 0 auto; text-align: left; }
            li { margin: 0 0 10px; }
            .card {
              background: #fefefe;
              padding: 12px 14px;
              border-radius: 6px;
              box-shadow: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.24);
            }
            .title { font-size: 1.05rem; font-weight: 500; color: #111; text-decoration: none; }
            a.title:hover { text-decoration: underline; }
            .meta { margin-top: 8px; font-size: 0.85rem; color: #555; word-break: break-all; }
            a.feed-url { color: #3498db; text-decoration: none; }
            a.feed-url:hover { text-decoration: underline; }
            footer { margin-top: 20px; }
            footer a { color: #fff; }

    """

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static func displayDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttr(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
