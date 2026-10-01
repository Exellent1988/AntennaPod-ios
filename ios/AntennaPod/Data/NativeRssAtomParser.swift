import Foundation

enum NativeRssAtomParser {
    static func parse(xml: String) throws -> PodcastFeed {
        guard let data = xml.data(using: .utf8) else {
            throw FeedParsingError.emptyResponse
        }
        let parser = XMLFeedParser(data: data)
        return try parser.parse()
    }
}

private final class XMLFeedParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var feedType: String?
    private var title: String?
    private var link: String?
    private var descriptionText: String?
    private var imageUrl: String?
    private var episodes: [PodcastEpisode] = []

    private var currentElement = ""
    private var currentText = ""
    private var inItem = false
    private var inImage = false

    private var itemTitle: String?
    private var itemLink: String?
    private var itemGuid: String?
    private var itemPubDate: String?
    private var itemDescription: String?
    private var enclosureUrl: String?
    private var enclosureType: String?
    private var enclosureLength: Int64 = 0
    private var transcriptUrl: String?
    private var transcriptType: String?
    private var transcriptPriority: Int = 0
    private var itemChapters: [PodcastChapter] = []
    private var podcastIndexChapterUrl: String?
    /// itunes:duration / media:content@duration → seconds; 0 = unknown.
    private var itemDurationSeconds: Double = 0
    private var elementStack: [String] = []

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() throws -> PodcastFeed {
        guard parser.parse() else {
            throw FeedParsingError.message(parser.parserError?.localizedDescription ?? "XML parse failed")
        }
        guard feedType != nil, title != nil || !episodes.isEmpty else {
            throw FeedParsingError.unsupported
        }
        return PodcastFeed(
            id: UUID(),
            title: title ?? "Podcast",
            feedUrl: "",
            siteLink: link,
            imageUrl: imageUrl,
            descriptionText: descriptionText,
            episodes: episodes
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = localName(elementName)
        elementStack.append(local)
        currentElement = local
        currentText = ""

        switch local.lowercased() {
        case "rss":
            feedType = "rss"
        case "feed":
            feedType = "atom"
        case "item", "entry":
            inItem = true
            itemTitle = nil
            itemLink = nil
            itemGuid = nil
            itemPubDate = nil
            itemDescription = nil
            enclosureUrl = nil
            enclosureType = nil
            enclosureLength = 0
            transcriptUrl = nil
            transcriptType = nil
            transcriptPriority = 0
            itemChapters = []
            podcastIndexChapterUrl = nil
            itemDurationSeconds = 0
            if local.lowercased() == "entry", let href = attributeDict["href"] {
                itemLink = href
            }
        case "image":
            if !inItem {
                inImage = true
            }
        case "enclosure":
            enclosureUrl = attributeDict["url"] ?? attributeDict["href"]
            enclosureType = attributeDict["type"]
            enclosureLength = Int64(attributeDict["length"] ?? attributeDict["fileSize"] ?? "0") ?? 0
        case "content":
            if attributeDict["url"] != nil {
                enclosureUrl = attributeDict["url"]
                enclosureType = attributeDict["type"]
                if enclosureType == nil, attributeDict["medium"] == "video" {
                    enclosureType = "video/*"
                }
                enclosureLength = Int64(attributeDict["fileSize"] ?? attributeDict["length"] ?? "0") ?? 0
                // Media RSS duration is seconds (integer); keep first positive value if itunes not set yet.
                if itemDurationSeconds <= 0,
                   let raw = attributeDict["duration"],
                   let seconds = EpisodeDurationParsing.seconds(from: raw),
                   seconds > 0 {
                    itemDurationSeconds = seconds
                }
            }
        case "link":
            let rel = attributeDict["rel"] ?? ""
            let href = attributeDict["href"]
            if inItem {
                if rel == "enclosure" {
                    enclosureUrl = href
                    enclosureType = attributeDict["type"]
                    enclosureLength = Int64(attributeDict["length"] ?? "0") ?? 0
                } else if rel.isEmpty || rel == "alternate" {
                    itemLink = href ?? itemLink
                }
            } else if rel.isEmpty || rel == "alternate" {
                link = href ?? link
            }
        case "transcript":
            // Podcast Index: <podcast:transcript url="…" type="application/json|text/vtt|application/srt"/>
            // Prefer JSON > VTT > SRT (AntennaPod Android TranscriptType priority).
            if inItem {
                let href = attributeDict["url"] ?? attributeDict["href"]
                let type = attributeDict["type"]
                if let href, !href.isEmpty {
                    let priority = TranscriptTypePreference.priority(forMime: type)
                    // Accept unknown/missing type at lowest priority so a lone URL still works.
                    let effective = priority > 0 ? priority : 1
                    if transcriptUrl == nil || effective > transcriptPriority {
                        transcriptUrl = href
                        transcriptType = type
                        transcriptPriority = effective
                    }
                }
            }
        case "chapters":
            // Podcast Index: <podcast:chapters url="https://…/chapters.json" type="application/json"/>
            if inItem {
                let url = attributeDict["url"] ?? attributeDict["href"]
                if let url, !url.isEmpty {
                    podcastIndexChapterUrl = url
                }
            }
        case "chapter":
            // Podlove Simple Chapters (psc:/sc:) — also works under Atom entries.
            if inItem, let startRaw = attributeDict["start"], !startRaw.isEmpty,
               let startSeconds = ChapterTimeParsing.seconds(from: startRaw) {
                let title = attributeDict["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let href = attributeDict["href"] ?? attributeDict["url"]
                let image = attributeDict["image"] ?? attributeDict["img"]
                itemChapters.append(
                    PodcastChapter(
                        title: (title?.isEmpty == false) ? title! : "Chapter",
                        startTimeSeconds: startSeconds,
                        href: href,
                        imageUrl: image
                    )
                )
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // Many feeds put HTML shownotes in CDATA (esp. content:encoded).
        if let s = String(data: CDATABlock, encoding: .utf8) {
            currentText += s
        } else if let s = String(data: CDATABlock, encoding: .isoLatin1) {
            currentText += s
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = localName(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            switch local.lowercased() {
            case "title":
                itemTitle = text
            case "link":
                if itemLink == nil, !text.isEmpty {
                    itemLink = text
                }
            case "guid", "id":
                itemGuid = text
            case "pubdate", "published", "updated":
                itemPubDate = text
            case "description", "summary", "content", "subtitle":
                // Prefer longer text so content:encoded / Atom content wins over short description.
                if !text.isEmpty {
                    let prev = itemDescription ?? ""
                    if text.count > prev.count {
                        itemDescription = text
                    }
                }
            case "duration":
                // itunes:duration (HH:MM:SS / MM:SS / seconds). Overrides media:content@duration when present.
                if let seconds = EpisodeDurationParsing.seconds(from: text), seconds > 0 {
                    itemDurationSeconds = seconds
                }
            case "item", "entry":
                let sorted = itemChapters.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
                let episode = PodcastEpisode(
                    id: itemGuid ?? itemLink ?? UUID().uuidString,
                    title: itemTitle ?? "Episode",
                    link: itemLink,
                    pubDateEpochMs: FeedDateParsing.epochMs(from: itemPubDate),
                    downloadUrl: enclosureUrl,
                    mimeType: enclosureType,
                    size: enclosureLength,
                    transcriptUrl: transcriptUrl,
                    transcriptType: transcriptType,
                    chapters: sorted,
                    podcastIndexChapterUrl: podcastIndexChapterUrl,
                    descriptionText: itemDescription,
                    durationSeconds: itemDurationSeconds
                )
                episodes.append(episode)
                inItem = false
            default:
                break
            }
        } else {
            switch local.lowercased() {
            case "title":
                title = text
            case "link":
                if link == nil, !text.isEmpty {
                    link = text
                }
            case "description", "subtitle", "summary":
                descriptionText = text
            case "url" where inImage:
                imageUrl = text
            case "logo", "icon":
                imageUrl = text
            case "image":
                inImage = false
            case "id":
                break
            default:
                break
            }
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        currentText = ""
        currentElement = elementStack.last ?? ""
    }

    private func localName(_ name: String) -> String {
        if let index = name.lastIndex(of: ":") {
            return String(name[name.index(after: index)...])
        }
        return name
    }
}

enum FeedDateParsing {
    static func epochMs(from raw: String?) -> Int64? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = rfc.date(from: raw) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        rfc.dateFormat = "dd MMM yy HH:mm:ss Z"
        if let date = rfc.date(from: raw) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        rfc.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        if let date = rfc.date(from: raw) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        return nil
    }
}

/// Podlove Simple Chapters / NPT-style start times → seconds.
enum ChapterTimeParsing {
    static func seconds(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            var idx = 0
            var total: Double = 0
            if parts.count == 3 {
                guard let hours = Double(parts[idx]) else { return nil }
                total += hours * 3600
                idx += 1
            }
            guard let minutes = Double(parts[idx]) else { return nil }
            total += minutes * 60
            idx += 1
            guard let secs = Double(parts[idx]) else { return nil }
            total += secs
            return total
        }

        return Double(trimmed)
    }
}

/// Episode duration from feed metadata (`itunes:duration`, Media RSS seconds).
/// Same formats as Android `DurationParser` / chapter NPT: `H:MM:SS`, `MM:SS`, or plain seconds.
enum EpisodeDurationParsing {
    static func seconds(from raw: String) -> Double? {
        ChapterTimeParsing.seconds(from: raw)
    }
}

/// Podcast Index transcript MIME preference (mirrors Android `TranscriptType`).
enum TranscriptTypePreference {
    /// Higher = preferred. JSON 4, VTT 3, SRT 2, unknown/empty 0.
    static func priority(forMime type: String?) -> Int {
        guard let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return 0
        }
        switch raw {
        case "application/json":
            return 4
        case "text/vtt":
            return 3
        case "application/srt", "application/srr", "application/x-subrip", "text/srt":
            return 2
        default:
            return 0
        }
    }

    static func canonicalMime(from type: String?) -> String? {
        guard let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "application/json":
            return "application/json"
        case "text/vtt":
            return "text/vtt"
        case "application/srt", "application/srr", "application/x-subrip", "text/srt":
            return "application/srt"
        default:
            return raw
        }
    }
}
