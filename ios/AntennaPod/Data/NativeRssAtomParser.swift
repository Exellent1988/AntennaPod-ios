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
    /// Prefer itunes:author (or RSS author text) → Atom author/name → managingEditor.
    private var itunesAuthor: String?
    private var atomAuthorName: String?
    private var managingEditor: String?
    /// Channel itunes:explicit — true only for yes/true/explicit.
    private var feedIsExplicit = false
    /// Prefer itunes:language / RSS language element → xml:lang on rss/feed/channel.
    private var languageElement: String?
    private var xmlLang: String?
    /// Prefer channel `podcast:funding` (url + optional text) over Atom `link rel="payment"`.
    private var fundingUrl: String?
    private var fundingLabel: String?
    private var fundingFromPodcastTag = false
    private var capturingFundingLabel = false
    /// Channel itunes:category `text` attributes (parent + nested), feed order; de-duped when building feed.
    private var categoryTexts: [String] = []
    /// Channel podcast:locked — true only for yes; false when absent/no. Display-only (no host verification).
    private var feedIsLocked = false
    private var lockedOwnerAttr: String?
    private var capturingLocked = false
    /// Channel podcast:guid — feed-provided UUIDv5 only; never invent / never generate from feed URL.
    private var podcastGuid: String?
    private var episodes: [PodcastEpisode] = []

    private var currentElement = ""
    private var currentText = ""
    private var inItem = false
    private var inImage = false
    /// Atom `<author>` / RSS itunes:author element at channel/feed level (not item).
    private var inFeedAuthor = false

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
    /// itunes:season — nil when absent / unparsable.
    private var itemSeasonNumber: Int?
    /// itunes:episode — nil when absent / unparsable.
    private var itemEpisodeNumber: Int?
    /// itunes:episodeType (`full` / `trailer` / `bonus`) — nil when absent / unknown.
    private var itemEpisodeType: String?
    /// Item itunes:explicit override; nil = inherit channel (or false when channel unmarked).
    private var itemExplicitOverride: Bool?
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
            author: Self.preferredAuthor(
                itunesAuthor: itunesAuthor,
                atomAuthorName: atomAuthorName,
                managingEditor: managingEditor
            ),
            isExplicit: feedIsExplicit,
            language: Self.preferredLanguage(
                languageElement: languageElement,
                xmlLang: xmlLang
            ),
            fundingUrl: fundingUrl,
            fundingLabel: fundingLabel,
            categories: Self.uniqueCategories(categoryTexts),
            isLocked: feedIsLocked,
            lockedOwner: lockedOwnerAttr,
            podcastGuid: podcastGuid,
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
            captureXmlLangIfNeeded(attributeDict)
        case "feed":
            feedType = "atom"
            captureXmlLangIfNeeded(attributeDict)
        case "channel":
            // RSS channel may carry xml:lang (language element is handled on endElement).
            captureXmlLangIfNeeded(attributeDict)
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
            itemSeasonNumber = nil
            itemEpisodeNumber = nil
            itemEpisodeType = nil
            itemExplicitOverride = nil
            if local.lowercased() == "entry", let href = attributeDict["href"] {
                itemLink = href
            }
        case "image":
            if !inItem {
                inImage = true
            }
        case "author":
            // Channel itunes:author (text) or Atom <author> wrapper — ignore item-level authors.
            if !inItem {
                inFeedAuthor = true
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
            } else if rel == "payment" {
                // Atom / atom:link rel="payment" — channel funding fallback when podcast:funding absent.
                if !fundingFromPodcastTag,
                   let href, !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if fundingUrl == nil {
                        fundingUrl = href.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } else if rel.isEmpty || rel == "alternate" {
                link = href ?? link
            }
        case "category":
            // itunes:category text="Technology" — parent and nested subcategory both fire here.
            // Channel-level only; store attribute text as provided — never invent App Store taxonomy.
            if !inItem {
                let raw = (attributeDict["text"] ?? attributeDict["Text"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let raw, !raw.isEmpty {
                    categoryTexts.append(raw)
                }
            }
        case "locked":
            // Podcast Index: <podcast:locked owner="email@…">yes|no</podcast:locked>
            // Channel-level claim for host transfer; display-only — we do not verify owner or block import.
            if !inItem {
                capturingLocked = true
                let owner = (attributeDict["owner"] ?? attributeDict["Owner"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let owner, !owner.isEmpty {
                    lockedOwnerAttr = owner
                }
            }
        case "funding":
            // Podcast Index: <podcast:funding url="https://…">Support the show!</podcast:funding>
            // Channel-level; first podcast:funding wins (may replace earlier Atom payment). Never invent URLs.
            if !inItem, !fundingFromPodcastTag {
                let href = (attributeDict["url"] ?? attributeDict["href"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let href, !href.isEmpty {
                    fundingUrl = href
                    fundingLabel = nil
                    fundingFromPodcastTag = true
                    capturingFundingLabel = true
                }
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
            case "season":
                // itunes:season — non-negative integer only; hide when missing/unparsable (never invent).
                if let n = ItunesSeasonEpisodeParsing.nonNegativeInt(from: text) {
                    itemSeasonNumber = n
                }
            case "episode":
                // itunes:episode — non-negative integer only; hide when missing/unparsable (never invent).
                if let n = ItunesSeasonEpisodeParsing.nonNegativeInt(from: text) {
                    itemEpisodeNumber = n
                }
            case "episodetype":
                // itunes:episodeType — full | trailer | bonus (Apple Podcasts).
                if let t = ItunesSeasonEpisodeParsing.episodeType(from: text) {
                    itemEpisodeType = t
                }
            case "explicit":
                // itunes:explicit — yes/true/explicit → true; no/false/clean → false (override).
                // Unknown/empty ignored (keep inherit).
                if let flagged = ItunesExplicitParsing.parse(text) {
                    itemExplicitOverride = flagged
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
                    durationSeconds: itemDurationSeconds,
                    seasonNumber: itemSeasonNumber,
                    episodeNumber: itemEpisodeNumber,
                    episodeType: itemEpisodeType,
                    isExplicit: itemExplicitOverride ?? feedIsExplicit
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
            case "author":
                // itunes:author / RSS author: text node on the element itself.
                // Atom wraps <name>/<email> — those set atomAuthorName; leave text empty here.
                if inFeedAuthor, !text.isEmpty {
                    itunesAuthor = text
                }
                inFeedAuthor = false
            case "name":
                // Atom <author><name>…</name></author> at feed level only.
                if inFeedAuthor, !text.isEmpty {
                    atomAuthorName = text
                }
            case "managingeditor":
                // RSS managingEditor — often "email (Name)"; store as provided, never invent.
                if !text.isEmpty {
                    managingEditor = text
                }
            case "explicit":
                // Channel itunes:explicit — only yes/true/explicit marks the feed.
                if let flagged = ItunesExplicitParsing.parse(text) {
                    feedIsExplicit = flagged
                }
            case "locked":
                // podcast:locked text must be yes/no per Podcast Index; yes → claim locked for transfer.
                if capturingLocked {
                    if let flagged = PodcastLockedParsing.parse(text) {
                        feedIsLocked = flagged
                    }
                    // Owner without a parseable yes/no stays stored but UI only shows when isLocked.
                    capturingLocked = false
                }
            case "funding":
                // podcast:funding text node = creator label (optional; may be truncated by aggregators ~128 chars).
                if capturingFundingLabel {
                    if !text.isEmpty {
                        fundingLabel = text
                    }
                    capturingFundingLabel = false
                }
            case "language":
                // RSS <language> / itunes:language — store as provided (never invent). Prefer over xml:lang.
                if !text.isEmpty {
                    languageElement = text
                }
            case "url" where inImage:
                imageUrl = text
            case "logo", "icon":
                imageUrl = text
            case "image":
                inImage = false
            case "guid":
                // Podcast Index <podcast:guid>…</podcast:guid> — channel-level only (item guid handled above).
                // Store first non-empty feed value as provided; never invent / never derive from feed URL.
                // Distinct from per-episode RSS <guid> / Atom <id>.
                if podcastGuid == nil, !text.isEmpty {
                    podcastGuid = text
                }
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

extension XMLFeedParser {
    /// Non-empty author preference: itunes/RSS author text → Atom name → managingEditor.
    /// Returns nil when none present (UI hides; never invents).
    fileprivate static func preferredAuthor(
        itunesAuthor: String?,
        atomAuthorName: String?,
        managingEditor: String?
    ) -> String? {
        for candidate in [itunesAuthor, atomAuthorName, managingEditor] {
            if let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw
            }
        }
        return nil
    }

    /// Non-empty language preference: RSS/itunes `<language>` element → `xml:lang` on rss/feed/channel.
    /// Returns nil when none present (UI hides; never invents codes).
    fileprivate static func preferredLanguage(
        languageElement: String?,
        xmlLang: String?
    ) -> String? {
        for candidate in [languageElement, xmlLang] {
            if let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw
            }
        }
        return nil
    }

    /// Trim + case-insensitive de-dupe of itunes:category texts, preserving first-seen order.
    fileprivate static func uniqueCategories(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    /// Capture `xml:lang` (or bare `lang`) once from root/channel attributes when still unset.
    fileprivate func captureXmlLangIfNeeded(_ attributeDict: [String: String]) {
        guard xmlLang == nil || xmlLang?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else {
            return
        }
        // Foundation may key as "xml:lang", "lang", or expand the namespace URI form.
        let candidates = [
            attributeDict["xml:lang"],
            attributeDict["lang"],
            attributeDict.first(where: { $0.key.lowercased().hasSuffix(":lang") || $0.key.lowercased() == "lang" })?.value
        ]
        for candidate in candidates {
            if let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                xmlLang = raw
                return
            }
        }
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

/// iTunes season / episode numbers and episodeType from feed text nodes.
/// Integers only (Apple Podcasts: non-negative). No sequential fabrication when absent.
enum ItunesSeasonEpisodeParsing {
    static func nonNegativeInt(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let n = Int(trimmed), n >= 0 else { return nil }
        return n
    }

    /// Canonical lowercase `full` / `trailer` / `bonus`, or `nil` when absent/unknown.
    static func episodeType(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "full", "trailer", "bonus":
            return trimmed
        default:
            return nil
        }
    }
}

/// Podcast Index `podcast:locked` channel text nodes.
/// Spec: `yes` / `no`. Also accept `true` / `false` for lenient feeds. Unknown/empty → nil (do not invent).
enum PodcastLockedParsing {
    static func parse(_ raw: String) -> Bool? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "yes", "true":
            return true
        case "no", "false":
            return false
        default:
            return nil
        }
    }
}

/// iTunes parental advisory from `itunes:explicit` text nodes.
/// Apple Podcasts: `yes` / `true` / `explicit` → explicit; `no` / `false` / `clean` → not explicit.
/// Unknown or empty → nil (do not invent; item inherits channel when override nil).
enum ItunesExplicitParsing {
    static func parse(_ raw: String) -> Bool? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "yes", "true", "explicit":
            return true
        case "no", "false", "clean":
            return false
        default:
            return nil
        }
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
