import Foundation

enum OpmlWriter {
    private static var title: String { String(localized: "AntennaPod Subscriptions") }

    /// Build OPML 2.0 XML matching Android `OpmlWriter` field names.
    /// `titleForFeed` supplies the outline text/title (display nickname when set).
    static func writeDocument(
        feeds: [PodcastFeed],
        titleForFeed: (PodcastFeed) -> String = { $0.title }
    ) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<opml version=\"2.0\">")
        lines.append("<head>")
        lines.append("<title>\(escape(title))</title>")
        lines.append("<dateCreated>\(escape(rfc822Date(Date())))</dateCreated>")
        lines.append("</head>")
        lines.append("<body>")
        for feed in feeds {
            guard !feed.feedUrl.isEmpty else { continue }
            guard !LocalFolderFeed.isLocalFolderFeed(feed) else { continue }
            let outlineTitle = titleForFeed(feed)
            var attrs = [
                "text=\"\(escapeAttr(outlineTitle))\"",
                "title=\"\(escapeAttr(outlineTitle))\"",
                "type=\"rss\"",
                "xmlUrl=\"\(escapeAttr(FeedURLNormalization.strippingCredentials(feed.feedUrl)))\""
            ]
            if let site = feed.siteLink, !site.isEmpty {
                attrs.append("htmlUrl=\"\(escapeAttr(site))\"")
            }
            lines.append("<outline \(attrs.joined(separator: " "))/>")
        }
        lines.append("</body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write OPML to a temporary file suitable for the share sheet.
    static func writeTemporaryFile(
        feeds: [PodcastFeed],
        titleForFeed: (PodcastFeed) -> String = { $0.title }
    ) throws -> URL {
        let xml = writeDocument(feeds: feeds, titleForFeed: titleForFeed)
        let dir = FileManager.default.temporaryDirectory
        let name = "AntennaPod-subscriptions-\(fileStamp()).opml"
        let url = dir.appendingPathComponent(name)
        guard let data = xml.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static func rfc822Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yy HH:mm:ss Z"
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
