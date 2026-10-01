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
    /// Channel podcast:person — feed-provided only; never invent people or default role/group.
    private var channelPeople: [PodcastPerson] = []
    /// Channel podcast:trailer — feed-provided only; never invent trailers.
    private var channelTrailers: [PodcastTrailer] = []
    /// Capturing podcast:trailer element text (title) + pending attributes.
    private var capturingTrailer = false
    private var pendingTrailerPubDate: String?
    private var pendingTrailerUrl: String?
    private var pendingTrailerLength: Int64?
    private var pendingTrailerType: String?
    private var pendingTrailerSeason: Int?
    /// Channel podcast:location — feed-provided only; never invent / never geocode.
    private var channelLocations: [PodcastLocation] = []
    /// Channel podcast:socialInteract — feed-provided only; never invent discussion URLs.
    private var channelSocialInteracts: [PodcastSocialInteract] = []
    /// Channel podcast:value / valueRecipient — feed-provided only; display-only (no payments).
    private var channelValues: [PodcastValue] = []
    /// Channel podcast:liveItem — feed-provided only; display-only (no live player / recording / chat).
    private var channelLiveItems: [PodcastLiveItem] = []
    private var episodes: [PodcastEpisode] = []

    private var currentElement = ""
    private var currentText = ""
    private var inItem = false
    /// Inside channel podcast:liveItem — capture title/link/guid/contentLink; do not create episodes / do not pollute channel title.
    private var inLiveItem = false
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
    /// Item podcast:person — feed-provided only; never invent.
    private var itemPeople: [PodcastPerson] = []
    /// Item podcast:location — feed-provided only; never invent / never geocode.
    private var itemLocations: [PodcastLocation] = []
    /// Item podcast:socialInteract — feed-provided only; never invent discussion URLs.
    private var itemSocialInteracts: [PodcastSocialInteract] = []
    /// Item podcast:value / valueRecipient — feed-provided only; display-only (no payments).
    private var itemValues: [PodcastValue] = []
    /// Item podcast:alternateEnclosure (+ nested source) — feed-provided only; display-only (Open/Copy; no player switch).
    private var itemAlternateEnclosures: [PodcastAlternateEnclosure] = []
    /// Capturing podcast:alternateEnclosure attributes + nested sources.
    private var capturingAlternateEnclosure = false
    private var pendingAltType: String?
    private var pendingAltLength: Int64?
    private var pendingAltBitrate: Double?
    private var pendingAltHeight: Int?
    private var pendingAltLang: String?
    private var pendingAltTitle: String?
    private var pendingAltRel: String?
    private var pendingAltCodecs: String?
    private var pendingAltDefault: Bool?
    private var pendingAltSources: [PodcastAlternateSource] = []
    /// Capturing podcast:source under alternateEnclosure.
    private var capturingAlternateSource = false
    private var pendingSourceUri: String?
    private var pendingSourceContentType: String?
    /// Capturing podcast:person element text (name) + pending attributes.
    private var capturingPerson = false
    private var pendingPersonRole: String?
    private var pendingPersonGroup: String?
    private var pendingPersonHref: String?
    private var pendingPersonImg: String?
    /// Capturing podcast:location element text (name) + pending attributes.
    private var capturingLocation = false
    private var pendingLocationGeo: String?
    private var pendingLocationOsm: String?
    private var pendingLocationRel: String?
    /// Capturing podcast:socialInteract (self-closing or with optional text URI fallback).
    private var capturingSocialInteract = false
    private var pendingSocialProtocol: String?
    private var pendingSocialUri: String?
    private var pendingSocialAccountId: String?
    private var pendingSocialPriority: Int?
    /// Capturing podcast:value (parent) + nested valueRecipient children.
    private var capturingValue = false
    private var pendingValueType: String?
    private var pendingValueMethod: String?
    private var pendingValueSuggested: String?
    private var pendingValueRecipients: [PodcastValueRecipient] = []
    /// Capturing podcast:valueRecipient attributes (typically self-closing).
    private var capturingValueRecipient = false
    private var pendingRecipientName: String?
    private var pendingRecipientType: String?
    private var pendingRecipientAddress: String?
    private var pendingRecipientSplit: Int?
    private var pendingRecipientFee: Bool?
    /// Capturing podcast:liveItem (channel) + nested title/link/guid/contentLink.
    private var pendingLiveStatus: PodcastLiveItemStatus?
    private var pendingLiveStart: String?
    private var pendingLiveEnd: String?
    private var pendingLiveTitle: String?
    private var pendingLiveLink: String?
    private var pendingLiveGuid: String?
    private var pendingLiveContentLinks: [PodcastContentLink] = []
    /// Capturing podcast:contentLink under liveItem (href attr + element text label).
    private var capturingContentLink = false
    private var pendingContentLinkHref: String?
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
            people: channelPeople,
            trailers: channelTrailers,
            locations: channelLocations,
            socialInteracts: channelSocialInteracts,
            values: channelValues,
            liveItems: channelLiveItems,
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
            // Nested item/entry inside liveItem would pollute episode list — ignore (liveItem is not an episode).
            if inLiveItem { break }
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
            itemPeople = []
            itemLocations = []
            itemSocialInteracts = []
            itemValues = []
            itemAlternateEnclosures = []
            capturingAlternateEnclosure = false
            pendingAltType = nil
            pendingAltLength = nil
            pendingAltBitrate = nil
            pendingAltHeight = nil
            pendingAltLang = nil
            pendingAltTitle = nil
            pendingAltRel = nil
            pendingAltCodecs = nil
            pendingAltDefault = nil
            pendingAltSources = []
            capturingAlternateSource = false
            pendingSourceUri = nil
            pendingSourceContentType = nil
            if local.lowercased() == "entry", let href = attributeDict["href"] {
                itemLink = href
            }
        case "image":
            if !inItem && !inLiveItem {
                inImage = true
            }
        case "author":
            // Channel itunes:author (text) or Atom <author> wrapper — ignore item-level authors.
            if !inItem && !inLiveItem {
                inFeedAuthor = true
            }
        case "enclosure":
            // Live stream enclosure is intentionally not stored for playback (display-only liveItem).
            if inLiveItem { break }
            enclosureUrl = attributeDict["url"] ?? attributeDict["href"]
            enclosureType = attributeDict["type"]
            enclosureLength = Int64(attributeDict["length"] ?? attributeDict["fileSize"] ?? "0") ?? 0
        case "content":
            if inLiveItem { break }
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
            if inLiveItem {
                // Live item page link (Atom-style href) — http(s) only used in UI; never invent.
                if rel.isEmpty || rel == "alternate" {
                    if let href, !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pendingLiveLink = href.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } else if inItem {
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
            if !inItem && !inLiveItem {
                let raw = (attributeDict["text"] ?? attributeDict["Text"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let raw, !raw.isEmpty {
                    categoryTexts.append(raw)
                }
            }
        case "locked":
            // Podcast Index: <podcast:locked owner="email@…">yes|no</podcast:locked>
            // Channel-level claim for host transfer; display-only — we do not verify owner or block import.
            if !inItem && !inLiveItem {
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
            if !inItem && !inLiveItem, !fundingFromPodcastTag {
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
        case "person":
            // Podcast Index: <podcast:person role="…" group="…" href="…" img="…">Name</podcast:person>
            // Channel and/or item. Name required; role/group/href/img optional — never invent people or default role/group.
            // Skip inside liveItem (display-only live metadata — do not attach people to channel/item from live children).
            if inLiveItem { break }
            capturingPerson = true
            pendingPersonRole = Self.nonEmptyAttr(attributeDict["role"] ?? attributeDict["Role"])
            pendingPersonGroup = Self.nonEmptyAttr(attributeDict["group"] ?? attributeDict["Group"])
            pendingPersonHref = Self.nonEmptyAttr(attributeDict["href"] ?? attributeDict["url"])
            pendingPersonImg = Self.nonEmptyAttr(attributeDict["img"] ?? attributeDict["image"])
        case "trailer":
            // Podcast Index: <podcast:trailer pubdate="…" url="…" length="…" type="…" season="…">Title</podcast:trailer>
            // Channel-level only. Title (element text) required to keep; url/pubdate/length/type/season optional here —
            // never invent trailers. Distinct from item itunes:episodeType=trailer.
            if !inItem && !inLiveItem {
                capturingTrailer = true
                pendingTrailerPubDate = Self.nonEmptyAttr(attributeDict["pubdate"] ?? attributeDict["pubDate"])
                pendingTrailerUrl = Self.nonEmptyAttr(attributeDict["url"] ?? attributeDict["href"])
                if let rawLen = Self.nonEmptyAttr(attributeDict["length"] ?? attributeDict["fileSize"]),
                   let len = Int64(rawLen) {
                    pendingTrailerLength = len
                } else {
                    pendingTrailerLength = nil
                }
                pendingTrailerType = Self.nonEmptyAttr(attributeDict["type"])
                if let rawSeason = Self.nonEmptyAttr(attributeDict["season"]),
                   let season = ItunesSeasonEpisodeParsing.nonNegativeInt(from: rawSeason) {
                    pendingTrailerSeason = season
                } else {
                    pendingTrailerSeason = nil
                }
            }
        case "location":
            // Podcast Index: <podcast:location geo="…" osm="…" rel="…">Name</podcast:location>
            // Channel and/or item. Name required; geo/osm/rel optional — never invent / never geocode names.
            if inLiveItem { break }
            capturingLocation = true
            pendingLocationGeo = Self.nonEmptyAttr(attributeDict["geo"])
            pendingLocationOsm = Self.nonEmptyAttr(attributeDict["osm"])
            pendingLocationRel = Self.nonEmptyAttr(attributeDict["rel"])
        case "socialinteract":
            // Podcast Index: <podcast:socialInteract protocol="…" uri="…" accountId="…" priority="…"/>
            // Channel and/or item. protocol + uri/url required for Discuss; accountId/priority optional.
            // protocol=disabled → stored but UI hides (no Discuss). Never invent URLs / no Fediverse client.
            if inLiveItem { break }
            capturingSocialInteract = true
            pendingSocialProtocol = Self.nonEmptyAttr(attributeDict["protocol"] ?? attributeDict["Protocol"])
            pendingSocialUri = Self.nonEmptyAttr(
                attributeDict["uri"] ?? attributeDict["url"] ?? attributeDict["href"]
            )
            pendingSocialAccountId = Self.nonEmptyAttr(
                attributeDict["accountId"] ?? attributeDict["accountid"] ?? attributeDict["account"]
            )
            if let rawPri = Self.nonEmptyAttr(attributeDict["priority"]),
               let pri = Int(rawPri) {
                pendingSocialPriority = pri
            } else {
                pendingSocialPriority = nil
            }
        case "value":
            // Podcast Index: <podcast:value type="…" method="…" suggested="…">…valueRecipient…</podcast:value>
            // Channel and/or item. type + method required; suggested optional. Display-only — no payments.
            if inLiveItem { break }
            capturingValue = true
            pendingValueType = Self.nonEmptyAttr(attributeDict["type"])
            pendingValueMethod = Self.nonEmptyAttr(attributeDict["method"])
            pendingValueSuggested = Self.nonEmptyAttr(attributeDict["suggested"])
            pendingValueRecipients = []
        case "valuerecipient":
            // Podcast Index: <podcast:valueRecipient name="…" type="…" address="…" split="…" fee="…"/>
            // Nested under podcast:value. type + address + split required; name recommended; fee optional.
            // Never invent addresses; never treat as actionable Lightning send in this app.
            guard capturingValue else { break }
            capturingValueRecipient = true
            pendingRecipientName = Self.nonEmptyAttr(attributeDict["name"])
            pendingRecipientType = Self.nonEmptyAttr(attributeDict["type"])
            pendingRecipientAddress = Self.nonEmptyAttr(attributeDict["address"])
            if let rawSplit = Self.nonEmptyAttr(attributeDict["split"]),
               let split = Int(rawSplit) {
                pendingRecipientSplit = split
            } else {
                pendingRecipientSplit = nil
            }
            if let rawFee = Self.nonEmptyAttr(attributeDict["fee"]) {
                let lower = rawFee.lowercased()
                if lower == "true" || lower == "yes" || lower == "1" {
                    pendingRecipientFee = true
                } else if lower == "false" || lower == "no" || lower == "0" {
                    pendingRecipientFee = false
                } else {
                    pendingRecipientFee = nil
                }
            } else {
                pendingRecipientFee = nil
            }
        case "liveitem":
            // Podcast Index: <podcast:liveItem status="…" start="…" end="…">…</podcast:liveItem>
            // Channel-level only. status + start required; end recommended. Children: title, link, guid, contentLink, …
            // Display-only — do not create episodes / do not play live enclosure / no chat / no payments.
            // Never invent live items.
            guard !inItem else { break }
            inLiveItem = true
            pendingLiveStatus = PodcastLiveItemStatus.parse(attributeDict["status"])
            pendingLiveStart = Self.nonEmptyAttr(attributeDict["start"])
            pendingLiveEnd = Self.nonEmptyAttr(attributeDict["end"])
            pendingLiveTitle = nil
            pendingLiveLink = nil
            pendingLiveGuid = nil
            pendingLiveContentLinks = []
            capturingContentLink = false
            pendingContentLinkHref = nil
        case "contentlink":
            // Podcast Index: <podcast:contentLink href="…">Label</podcast:contentLink>
            // Under liveItem (fallback / platform links). href required; text = label. openURL only — no live player.
            guard inLiveItem else { break }
            capturingContentLink = true
            pendingContentLinkHref = Self.nonEmptyAttr(attributeDict["href"] ?? attributeDict["url"])
        case "alternateenclosure":
            // Podcast Index: <podcast:alternateEnclosure type="…" length="…" bitrate="…" …>
            // Item-level only. type required; ≥1 podcast:source. Display-only — Open URL / Copy; no player switch.
            // Never invent alternate enclosures.
            if inLiveItem { break }
            guard inItem else { break }
            capturingAlternateEnclosure = true
            pendingAltType = Self.nonEmptyAttr(attributeDict["type"])
            if let rawLen = Self.nonEmptyAttr(attributeDict["length"]),
               let len = Int64(rawLen), len >= 0 {
                pendingAltLength = len
            } else {
                pendingAltLength = nil
            }
            if let rawBr = Self.nonEmptyAttr(attributeDict["bitrate"]),
               let br = Double(rawBr), br > 0 {
                pendingAltBitrate = br
            } else {
                pendingAltBitrate = nil
            }
            if let rawH = Self.nonEmptyAttr(attributeDict["height"]),
               let h = Int(rawH), h > 0 {
                pendingAltHeight = h
            } else {
                pendingAltHeight = nil
            }
            pendingAltLang = Self.nonEmptyAttr(attributeDict["lang"] ?? attributeDict["language"])
            pendingAltTitle = Self.nonEmptyAttr(attributeDict["title"])
            pendingAltRel = Self.nonEmptyAttr(attributeDict["rel"])
            pendingAltCodecs = Self.nonEmptyAttr(attributeDict["codecs"])
            if let rawDef = Self.nonEmptyAttr(attributeDict["default"]) {
                let lower = rawDef.lowercased()
                if lower == "true" || lower == "yes" || lower == "1" {
                    pendingAltDefault = true
                } else if lower == "false" || lower == "no" || lower == "0" {
                    pendingAltDefault = false
                } else {
                    pendingAltDefault = nil
                }
            } else {
                pendingAltDefault = nil
            }
            pendingAltSources = []
            capturingAlternateSource = false
            pendingSourceUri = nil
            pendingSourceContentType = nil
        case "source":
            // Podcast Index: <podcast:source uri="…" contentType="…"/> under alternateEnclosure.
            // uri required; contentType optional (when transport MIME differs).
            guard capturingAlternateEnclosure, inItem, !inLiveItem else { break }
            capturingAlternateSource = true
            pendingSourceUri = Self.nonEmptyAttr(
                attributeDict["uri"] ?? attributeDict["url"] ?? attributeDict["href"]
            )
            pendingSourceContentType = Self.nonEmptyAttr(
                attributeDict["contentType"] ?? attributeDict["type"]
            )
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

        if inLiveItem {
            switch local.lowercased() {
            case "title":
                if !text.isEmpty {
                    pendingLiveTitle = text
                }
            case "link":
                if pendingLiveLink == nil, !text.isEmpty {
                    pendingLiveLink = text
                }
            case "guid", "id":
                if !text.isEmpty {
                    pendingLiveGuid = text
                }
            case "contentlink":
                finishContentLink(text: text)
            case "liveitem":
                finishLiveItem()
            default:
                break
            }
        } else if inItem {
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
            case "person":
                finishPerson(text: text, intoItem: true)
            case "location":
                finishLocation(text: text, intoItem: true)
            case "socialinteract":
                finishSocialInteract(text: text, intoItem: true)
            case "valuerecipient":
                finishValueRecipient()
            case "value":
                finishValue(intoItem: true)
            case "source":
                finishAlternateSource()
            case "alternateenclosure":
                finishAlternateEnclosure()
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
                    isExplicit: itemExplicitOverride ?? feedIsExplicit,
                    people: itemPeople,
                    locations: itemLocations,
                    socialInteracts: itemSocialInteracts,
                    values: itemValues,
                    alternateEnclosures: itemAlternateEnclosures
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
            case "person":
                finishPerson(text: text, intoItem: false)
            case "trailer":
                finishTrailer(text: text)
            case "location":
                finishLocation(text: text, intoItem: false)
            case "socialinteract":
                finishSocialInteract(text: text, intoItem: false)
            case "valuerecipient":
                finishValueRecipient()
            case "value":
                finishValue(intoItem: false)
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



    /// Finish podcast:source under alternateEnclosure — append when uri present; never invent.
    private func finishAlternateSource() {
        defer {
            capturingAlternateSource = false
            pendingSourceUri = nil
            pendingSourceContentType = nil
        }
        guard capturingAlternateEnclosure, capturingAlternateSource else { return }
        guard let uri = pendingSourceUri,
              !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingAltSources.append(
            PodcastAlternateSource(
                uri: uri,
                contentType: pendingSourceContentType
            )
        )
    }

    /// Finish podcast:alternateEnclosure — append when type + ≥1 source; display-only (no player switch).
    private func finishAlternateEnclosure() {
        defer {
            capturingAlternateEnclosure = false
            pendingAltType = nil
            pendingAltLength = nil
            pendingAltBitrate = nil
            pendingAltHeight = nil
            pendingAltLang = nil
            pendingAltTitle = nil
            pendingAltRel = nil
            pendingAltCodecs = nil
            pendingAltDefault = nil
            pendingAltSources = []
            capturingAlternateSource = false
            pendingSourceUri = nil
            pendingSourceContentType = nil
        }
        guard capturingAlternateEnclosure, inItem else { return }
        guard let mime = pendingAltType,
              !mime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sources = pendingAltSources
        guard !sources.isEmpty else { return }
        itemAlternateEnclosures.append(
            PodcastAlternateEnclosure(
                type: mime,
                length: pendingAltLength,
                bitrate: pendingAltBitrate,
                height: pendingAltHeight,
                lang: pendingAltLang,
                title: pendingAltTitle,
                rel: pendingAltRel,
                codecs: pendingAltCodecs,
                isDefault: pendingAltDefault,
                sources: sources
            )
        )
    }

    /// Finish podcast:contentLink under liveItem — append when href present; never invent.
    private func finishContentLink(text: String) {
        defer {
            capturingContentLink = false
            pendingContentLinkHref = nil
        }
        guard inLiveItem, capturingContentLink else { return }
        guard let href = pendingContentLinkHref,
              !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingLiveContentLinks.append(
            PodcastContentLink(
                href: href,
                label: label.isEmpty ? nil : label
            )
        )
    }

    /// Finish channel podcast:liveItem — append when status + start present; display-only (no episode / no player).
    private func finishLiveItem() {
        defer {
            inLiveItem = false
            pendingLiveStatus = nil
            pendingLiveStart = nil
            pendingLiveEnd = nil
            pendingLiveTitle = nil
            pendingLiveLink = nil
            pendingLiveGuid = nil
            pendingLiveContentLinks = []
            capturingContentLink = false
            pendingContentLinkHref = nil
        }
        guard inLiveItem else { return }
        guard let status = pendingLiveStatus,
              let start = pendingLiveStart,
              !start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let end = pendingLiveEnd
        channelLiveItems.append(
            PodcastLiveItem(
                status: status,
                start: start,
                startEpochMs: FeedDateParsing.epochMs(from: start),
                end: end,
                endEpochMs: FeedDateParsing.epochMs(from: end),
                title: pendingLiveTitle,
                link: pendingLiveLink,
                guid: pendingLiveGuid,
                contentLinks: pendingLiveContentLinks
            )
        )
    }

    /// Finish a podcast:person element — append when name non-empty; never invent.
    private func finishPerson(text: String, intoItem: Bool) {
        defer {
            capturingPerson = false
            pendingPersonRole = nil
            pendingPersonGroup = nil
            pendingPersonHref = nil
            pendingPersonImg = nil
        }
        guard capturingPerson else { return }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let person = PodcastPerson(
            name: name,
            role: pendingPersonRole,
            group: pendingPersonGroup,
            href: pendingPersonHref,
            img: pendingPersonImg
        )
        if intoItem {
            itemPeople.append(person)
        } else {
            channelPeople.append(person)
        }
    }

    /// Finish a channel podcast:trailer — append when title non-empty; never invent.
    private func finishTrailer(text: String) {
        defer {
            capturingTrailer = false
            pendingTrailerPubDate = nil
            pendingTrailerUrl = nil
            pendingTrailerLength = nil
            pendingTrailerType = nil
            pendingTrailerSeason = nil
        }
        guard capturingTrailer else { return }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let pub = pendingTrailerPubDate
        channelTrailers.append(
            PodcastTrailer(
                title: title,
                pubDate: pub,
                pubDateEpochMs: FeedDateParsing.epochMs(from: pub),
                url: pendingTrailerUrl,
                length: pendingTrailerLength,
                type: pendingTrailerType,
                season: pendingTrailerSeason
            )
        )
    }

    /// Finish a podcast:location element — append when name non-empty; never invent / never geocode.
    private func finishLocation(text: String, intoItem: Bool) {
        defer {
            capturingLocation = false
            pendingLocationGeo = nil
            pendingLocationOsm = nil
            pendingLocationRel = nil
        }
        guard capturingLocation else { return }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let location = PodcastLocation(
            name: name,
            geo: pendingLocationGeo,
            osm: pendingLocationOsm,
            rel: pendingLocationRel
        )
        if intoItem {
            itemLocations.append(location)
        } else {
            channelLocations.append(location)
        }
    }


    /// Finish a podcast:valueRecipient — append when type + address + split present; never invent.
    private func finishValueRecipient() {
        defer {
            capturingValueRecipient = false
            pendingRecipientName = nil
            pendingRecipientType = nil
            pendingRecipientAddress = nil
            pendingRecipientSplit = nil
            pendingRecipientFee = nil
        }
        guard capturingValue, capturingValueRecipient else { return }
        guard let rType = pendingRecipientType,
              !rType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let address = pendingRecipientAddress,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let split = pendingRecipientSplit else { return }
        pendingValueRecipients.append(
            PodcastValueRecipient(
                name: pendingRecipientName,
                type: rType,
                address: address,
                split: split,
                fee: pendingRecipientFee
            )
        )
    }

    /// Finish a podcast:value block — append when type + method present and ≥1 recipient; display-only.
    private func finishValue(intoItem: Bool) {
        defer {
            capturingValue = false
            pendingValueType = nil
            pendingValueMethod = nil
            pendingValueSuggested = nil
            pendingValueRecipients = []
        }
        guard capturingValue else { return }
        guard let vType = pendingValueType,
              !vType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let vMethod = pendingValueMethod,
              !vMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let recipients = pendingValueRecipients
        guard !recipients.isEmpty else { return }
        let block = PodcastValue(
            type: vType,
            method: vMethod,
            suggested: pendingValueSuggested,
            recipients: recipients
        )
        if intoItem {
            itemValues.append(block)
        } else {
            channelValues.append(block)
        }
    }

    /// Finish a podcast:socialInteract — append when protocol present; uri from attr or http(s) element text.
    /// `protocol=disabled` may omit uri (still stored so UI can hide). Never invent URLs.
    private func finishSocialInteract(text: String, intoItem: Bool) {
        defer {
            capturingSocialInteract = false
            pendingSocialProtocol = nil
            pendingSocialUri = nil
            pendingSocialAccountId = nil
            pendingSocialPriority = nil
        }
        guard capturingSocialInteract else { return }
        guard let proto = pendingSocialProtocol,
              !proto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var uri = pendingSocialUri?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Older feeds put the URL in element text; accept only when it looks like http(s).
        if uri.isEmpty {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = URL(string: body),
               let scheme = parsed.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                uri = body
            }
        }
        let isDisabled = proto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disabled"
        // Disabled may have empty uri; openable entries need a uri string (UI still requires http(s)).
        if !isDisabled && uri.isEmpty { return }
        let interact = PodcastSocialInteract(
            protocolName: proto,
            uri: uri,
            accountId: pendingSocialAccountId,
            priority: pendingSocialPriority
        )
        if intoItem {
            itemSocialInteracts.append(interact)
        } else {
            channelSocialInteracts.append(interact)
        }
    }
    private func localName(_ name: String) -> String {
        if let index = name.lastIndex(of: ":") {
            return String(name[name.index(after: index)...])
        }
        return name
    }
}

extension XMLFeedParser {

    /// Trimmed non-empty attribute value, or nil.
    fileprivate static func nonEmptyAttr(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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
        // Normalize common Podcast Index liveItem offsets like …-0600 → …-06:00 for ISO8601DateFormatter.
        let normalized = normalizeISO8601Offset(raw)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: normalized) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: normalized) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        if normalized != raw {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: raw) {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
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

    /// Insert a colon in timezone offsets like `-0600` / `+0530` so `ISO8601DateFormatter` accepts them.
    /// Leaves already-colonized / Z / bare strings unchanged. Never invents a timestamp.
    private static func normalizeISO8601Offset(_ raw: String) -> String {
        // Match …±HHMM at end (no colon).
        guard raw.count >= 5 else { return raw }
        let tail = raw.suffix(5)
        let sign = tail.first
        guard sign == "+" || sign == "-" else { return raw }
        let digits = tail.dropFirst()
        guard digits.count == 4, digits.allSatisfy(\.isNumber) else { return raw }
        // Already has colon before offset? e.g. …T12:00:00-06:00 won't match 5-char ±HHMM tail.
        let hh = digits.prefix(2)
        let mm = digits.suffix(2)
        return String(raw.dropLast(5)) + "\(sign!)\(hh):\(mm)"
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
