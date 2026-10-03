import Foundation

/// AntennaPod-style HTML export lite for subscriptions (self-contained list).
/// Distinct from OPML and the iOS JSON ZIP backup.
/// Metadata (author, language, categories, funding) is included only when the feed provides it — never invented.
/// Local folder podcasts are omitted (same as OPML).
enum HtmlExportWriter {
    private static var documentTitle: String { String(localized: "AntennaPod Subscriptions") }
    /// Fallback document `lang` when feeds disagree or lack a shared language code.
    private static let fallbackDocumentLang = "en"

    /// Build a simple self-contained HTML document: title, feed URL links, optional episode count,
    /// plus author / language / categories / funding when the feed provides them.
    static func writeDocument(
        feeds: [PodcastFeed],
        includeEpisodeCount: Bool = true,
        titleForFeed: (PodcastFeed) -> String = { $0.title }
    ) -> String {
        let sorted = feeds.sorted {
            titleForFeed($0).localizedCaseInsensitiveCompare(titleForFeed($1)) == .orderedAscending
        }
        let exportable = sorted.filter { feed in
            !feed.feedUrl.isEmpty && !LocalFolderFeed.isLocalFolderFeed(feed)
        }
        // Prefer first feed’s language when every exportable feed shares that code; else keep `en`.
        let docLang = sharedDocumentLanguage(of: exportable) ?? fallbackDocumentLang

        var body = ""
        body += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        body += "<!DOCTYPE html>\n"
        // Comment: document lang is shared feed language when unanimous; otherwise en (mixed / missing).
        body += "<!-- lang: shared feed language when all exportable feeds agree; else en -->\n"
        body += "<html lang=\"\(escapeAttr(docLang))\">\n"
        body += "<head>\n"
        body += "  <meta charset=\"UTF-8\" />\n"
        body += "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n"
        body += "  <meta name=\"generator\" content=\"AntennaPod iOS\" />\n"
        let metaDescription = String(localized: "Subscription list exported from AntennaPod iOS. Local folder podcasts are omitted. Author, language, categories, and funding appear only when provided by each feed.")
        body += "  <meta name=\"description\" content=\"\(escapeAttr(metaDescription))\" />\n"
        body += "  <title>\(escape(documentTitle))</title>\n"
        body += "  <style>\n"
        body += css
        body += "  </style>\n"
        body += "</head>\n"
        body += "<body>\n"
        body += "  <header>\n"
        body += "    <h1>\(escape(documentTitle))</h1>\n"
        let exportedAt = displayDate(Date())
        let count = exportable.count
        let summary = count == 1
            ? String(localized: "\(count) subscription · exported \(exportedAt)")
            : String(localized: "\(count) subscriptions · exported \(exportedAt)")
        body += "    <p class=\"meta\">\(escape(summary))</p>\n"
        body += "  </header>\n"
        body += "  <ul class=\"feeds\">\n"
        for feed in exportable {
            body += feedItemHTML(feed: feed, includeEpisodeCount: includeEpisodeCount, title: titleForFeed(feed))
        }
        body += "  </ul>\n"
        body += "  <footer>\n"
        let footer = String(localized: "Exported from AntennaPod iOS · local folder podcasts omitted · metadata only when provided by each feed · ")
        body += "    <p>\(escape(footer))"
        body += "<a href=\"https://antennapod.org\">antennapod.org</a></p>\n"
        body += "  </footer>\n"
        body += "</body>\n"
        body += "</html>\n"
        return body
    }

    /// Write HTML to a temporary file suitable for the share sheet.
    static func writeTemporaryFile(
        feeds: [PodcastFeed],
        includeEpisodeCount: Bool = true,
        titleForFeed: (PodcastFeed) -> String = { $0.title }
    ) throws -> URL {
        let html = writeDocument(feeds: feeds, includeEpisodeCount: includeEpisodeCount, titleForFeed: titleForFeed)
        let dir = FileManager.default.temporaryDirectory
        let name = "AntennaPod-subscriptions-\(fileStamp()).html"
        let url = dir.appendingPathComponent(name)
        guard let data = html.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Shared language code when every exportable feed has the same non-empty code (case-insensitive).
    /// Uses the first feed’s original casing for `html lang`. Nil when empty list, any missing, or mixed.
    private static func sharedDocumentLanguage(of feeds: [PodcastFeed]) -> String? {
        guard let firstCode = feeds.first?.languageCode else { return nil }
        let shared = firstCode
        for feed in feeds {
            guard let code = feed.languageCode else { return nil }
            if code.caseInsensitiveCompare(shared) != .orderedSame {
                return nil
            }
        }
        return shared
    }

    private static func feedItemHTML(feed: PodcastFeed, includeEpisodeCount: Bool, title: String) -> String {
        // Title links to site when feed provides a usable http(s) siteLink (existing behavior).
        let titleHTML: String
        if let siteURL = feed.websiteURL {
            titleHTML = "<a class=\"title\" href=\"\(escapeAttr(siteURL.absoluteString))\">\(escape(title))</a>"
        } else if let site = feed.siteLink?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty {
            // Preserve prior attr escape for non-http(s) site strings when present (rare).
            titleHTML = "<a class=\"title\" href=\"\(escapeAttr(site))\">\(escape(title))</a>"
        } else {
            titleHTML = "<span class=\"title\">\(escape(title))</span>"
        }

        var metaParts: [String] = []
        metaParts.append(
            "<a class=\"feed-url\" href=\"\(escapeAttr(feed.feedUrl))\">\(escape(feed.feedUrl))</a>"
        )
        if let author = feed.displayAuthor {
            metaParts.append(escape(author))
        }
        if let language = feed.displayLanguage {
            metaParts.append(escape(language))
        }
        if let cats = feed.categoriesCaption {
            metaParts.append(escape(cats))
        }
        if includeEpisodeCount {
            let n = feed.episodes.count
            let episodeCount = n == 1
                ? "\(n) \(String(localized: "Episode"))"
                : String(localized: "\(n) episodes")
            metaParts.append(escape(episodeCount))
        }
        if let funding = feed.fundingURL {
            let label = feed.displayFundingLabel ?? String(localized: "Support")
            metaParts.append(
                "<a class=\"funding\" href=\"\(escapeAttr(funding.absoluteString))\">\(escape(label))</a>"
            )
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
            a.feed-url, a.funding { color: #3498db; text-decoration: none; }
            a.feed-url:hover, a.funding:hover { text-decoration: underline; }
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
        f.locale = .autoupdatingCurrent
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
