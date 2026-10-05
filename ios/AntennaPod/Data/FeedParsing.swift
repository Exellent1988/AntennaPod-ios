import Foundation

enum FeedParsingError: Error, LocalizedError {
    case emptyResponse
    case unsupported
    case message(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Feed was empty"
        case .unsupported:
            return "Unsupported feed format"
        case .message(let text):
            return text
        }
    }
}

enum FeedParsing {
    static func parse(xml: String) throws -> PodcastFeed {
        try NativeRssAtomParser.parse(xml: xml)
    }

    /// Enclosure, transcript, chapters, episode / website, and other opened links given as a relative
    /// (`/media/ep1.mp3`, `ep1.mp3`) or protocol-relative (`//cdn.example.com/ep1.mp3`)
    /// path cannot be played, downloaded, or opened. Resolve them against the fetched feed
    /// URL. Runs after parsing, so episode ids (built from the raw values) do not change.
    /// Values that already have a scheme, and artwork, are left as they are.
    static func resolvingRelativeLinks(in feed: PodcastFeed, against base: URL) -> PodcastFeed {
        var feed = feed
        feed.siteLink = absoluteLink(feed.siteLink, base: base)
        // Funding, person, social, live item, and podroll / publisher links are opened or
        // played from the UI. Trailers are left out: their playback id is built from the URL.
        feed.fundingUrl = absoluteLink(feed.fundingUrl, base: base)
        feed.people = resolvingPeople(feed.people, base: base)
        feed.socialInteracts = resolvingSocialInteracts(feed.socialInteracts, base: base)
        for index in feed.liveItems.indices {
            feed.liveItems[index].link = absoluteLink(feed.liveItems[index].link, base: base)
            for link in feed.liveItems[index].contentLinks.indices {
                let href = feed.liveItems[index].contentLinks[link].href
                feed.liveItems[index].contentLinks[link].href = absoluteLink(href, base: base) ?? href
            }
        }
        for index in feed.podrollItems.indices {
            feed.podrollItems[index].feedUrl = absoluteLink(feed.podrollItems[index].feedUrl, base: base)
        }
        for index in feed.publisherItems.indices {
            feed.publisherItems[index].feedUrl = absoluteLink(feed.publisherItems[index].feedUrl, base: base)
        }
        for index in feed.episodes.indices {
            feed.episodes[index].link = absoluteLink(feed.episodes[index].link, base: base)
            feed.episodes[index].downloadUrl = absoluteLink(feed.episodes[index].downloadUrl, base: base)
            feed.episodes[index].transcriptUrl = absoluteLink(feed.episodes[index].transcriptUrl, base: base)
            feed.episodes[index].podcastIndexChapterUrl = absoluteLink(
                feed.episodes[index].podcastIndexChapterUrl,
                base: base
            )
            feed.episodes[index].people = resolvingPeople(feed.episodes[index].people, base: base)
            feed.episodes[index].socialInteracts = resolvingSocialInteracts(
                feed.episodes[index].socialInteracts,
                base: base
            )
            for enclosure in feed.episodes[index].alternateEnclosures.indices {
                for source in feed.episodes[index].alternateEnclosures[enclosure].sources.indices {
                    let uri = feed.episodes[index].alternateEnclosures[enclosure].sources[source].uri
                    feed.episodes[index].alternateEnclosures[enclosure].sources[source].uri =
                        absoluteLink(uri, base: base) ?? uri
                }
            }
        }
        return feed
    }

    private static func resolvingPeople(_ people: [PodcastPerson], base: URL) -> [PodcastPerson] {
        people.map { person in
            var person = person
            person.href = absoluteLink(person.href, base: base)
            return person
        }
    }

    private static func resolvingSocialInteracts(
        _ items: [PodcastSocialInteract],
        base: URL
    ) -> [PodcastSocialInteract] {
        items.map { item in
            var item = item
            item.uri = absoluteLink(item.uri, base: base) ?? item.uri
            return item
        }
    }

    /// `raw` resolved against `base` when it has no scheme and resolves to http(s); else `raw`.
    static func absoluteLink(_ raw: String?, base: URL) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              parsed.scheme == nil,
              let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return raw
        }
        return resolved.absoluteString
    }

    /// Decode a body that is not valid UTF-8. Many feeds labeled ISO-8859-1 are really
    /// windows-1252, whose 0x80–0x9F bytes are €, curly quotes, and dashes; Latin-1 turns
    /// them into invisible C1 controls. 0xA0–0xFF map the same in both. Latin-1 stays the
    /// last fallback because windows-1252 leaves five bytes undefined.
    static func decodeLegacy8Bit(_ data: Data) -> String? {
        String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    /// `parse(xml:)` hands XMLParser the string as UTF-8 bytes, but XMLParser still honors
    /// an `encoding="ISO-8859-1"` / `windows-1252` declaration and would read those bytes
    /// as Latin-1 (`é` → `Ã©`). Use only after decoding a non-UTF-8 body as Latin-1:
    /// rewrites the encoding value of the leading XML declaration (optional BOM /
    /// whitespace before it) to `UTF-8`. Everything else is left unchanged.
    static func declaringUTF8(_ xml: String) -> String {
        let pattern = #"^[\x{FEFF}\s]*<\?xml\b[^>]*?\bencoding\s*=\s*("[^"]*"|'[^']*')"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let valueRange = Range(match.range(at: 1), in: xml)
        else {
            return xml
        }
        let quote = xml[valueRange].first.map(String.init) ?? "\""
        return xml.replacingCharacters(in: valueRange, with: quote + "UTF-8" + quote)
    }
}
