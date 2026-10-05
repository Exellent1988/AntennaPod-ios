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
    /// Channel podcast:medium — raw feed string (podcast/music/video/…); nil when absent. Display-only; never invent/remap.
    private var channelMedium: String?
    /// Channel itunes:type — raw feed string (episodic/serial/…); nil when absent. Never invent. Capsule display-only; Serial nil-only Oldest-first heuristic is separate.
    private var channelItunesType: String?
    /// Channel podcast:updateFrequency — structured text + optional rrule/dtstart/complete; nil when absent. Display-only; never invent; does not change Keep updated/refresh.
    private var channelUpdateFrequency: PodcastUpdateFrequency?
    private var capturingUpdateFrequency = false
    private var pendingUpdateFrequencyRrule: String?
    private var pendingUpdateFrequencyDtstart: String?
    private var pendingUpdateFrequencyComplete: Bool?
    /// Channel itunes:complete — true only for yes/true. Display-only; never invent; does not change Keep updated/refresh.
    /// Distinct from podcast:updateFrequency complete attribute.
    private var feedIsItunesComplete = false
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
    /// Channel podcast:block / itunes:block — true when any yes/true. Display-only (directories; no subscribe/play enforcement).
    private var feedIsBlocked = false
    private var capturingBlock = false
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
    /// Channel podcast:txt — feed-provided only; display-only (Copy / Open http(s); no Social / Matrix clients).
    private var channelTexts: [PodcastTxt] = []
    /// Channel podcast:license — feed-provided only; display-only (text + Open http(s) / Copy; no DRM).
    private var channelLicenses: [PodcastLicense] = []
    /// Channel podcast:images / podcast:image — feed-provided only; store URL+width; prefer one for artwork (no eager multi-download).
    private var channelImages: [PodcastImageVariant] = []
    /// Channel podcast:podroll / nested remoteItem — feed-provided only; display-only (Open / Copy / Subscribe preview).
    private var channelPodrollItems: [PodcastRemoteItem] = []
    /// Inside channel podcast:podroll — capture nested remoteItem only; do not invent recommendations.
    private var inPodroll = false
    /// Channel podcast:publisher / nested remoteItem — feed-provided only; display-only (Open / Copy / Subscribe preview).
    private var channelPublisherItems: [PodcastRemoteItem] = []
    /// Inside channel podcast:publisher — capture nested remoteItem only; do not invent publishers.
    private var inPublisher = false
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
    /// `itemPubDate` came from Atom `updated`, so a `pubDate` / `published` may still replace it.
    private var itemPubDateIsUpdated = false
    private var itemDescription: String?
    private var enclosureUrl: String?
    private var enclosureType: String?
    private var enclosureLength: Int64 = 0
    private var transcriptUrl: String?
    private var transcriptType: String?
    private var transcriptLanguage: String?
    private var transcriptPriority: Int = 0
    private var itemChapters: [PodcastChapter] = []
    private var podcastIndexChapterUrl: String?
    private var podcastIndexChapterType: String?
    /// itunes:duration / media:content@duration → seconds; 0 = unknown.
    private var itemDurationSeconds: Double = 0
    /// itunes:season — nil when absent / unparsable.
    private var itemSeasonNumber: Int?
    /// itunes:episode — nil when absent / unparsable.
    private var itemEpisodeNumber: Int?
    /// itunes:episodeType — raw feed string (full/trailer/bonus/…); nil when absent. Display localizes known; unknown → raw.
    private var itemEpisodeType: String?
    /// Item itunes:explicit override; nil = inherit channel (or false when channel unmarked).
    private var itemExplicitOverride: Bool?
    /// Item podcast:medium — raw feed string when present; nil when absent. Display-only; never invent/remap.
    private var itemMedium: String?
    /// Item podcast:person — feed-provided only; never invent.
    private var itemPeople: [PodcastPerson] = []
    /// Item podcast:location — feed-provided only; never invent / never geocode.
    private var itemLocations: [PodcastLocation] = []
    /// Item podcast:socialInteract — feed-provided only; never invent discussion URLs.
    private var itemSocialInteracts: [PodcastSocialInteract] = []
    /// Item podcast:value / valueRecipient — feed-provided only; display-only (no payments).
    private var itemValues: [PodcastValue] = []
    /// Item podcast:alternateEnclosure (+ nested source) — feed-provided only; http(s) Play via preferredMediaURL / else Copy.
    private var itemAlternateEnclosures: [PodcastAlternateEnclosure] = []
    /// Item podcast:soundbite — feed-provided only; display / seek-to-start when current episode (no clip player).
    private var itemSoundbites: [PodcastSoundbite] = []
    /// Capturing podcast:soundbite attributes + optional title text.
    private var capturingSoundbite = false
    private var pendingSoundbiteStart: Double?
    private var pendingSoundbiteDuration: Double?
    /// Item podcast:txt — feed-provided only; display-only (Copy / Open http(s); no Social / Matrix clients).
    private var itemTexts: [PodcastTxt] = []
    /// Capturing podcast:txt optional purpose + element text.
    private var capturingTxt = false
    private var pendingTxtPurpose: String?
    /// Item podcast:license — feed-provided only; display-only (text + Open http(s) / Copy; no DRM).
    private var itemLicenses: [PodcastLicense] = []
    /// Capturing podcast:license optional url + element text.
    private var capturingLicense = false
    private var pendingLicenseUrl: String?
    /// Item podcast:images / podcast:image — feed-provided only; store URL+width; prefer one for artwork.
    private var itemImages: [PodcastImageVariant] = []
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
        // When only podcast:images / podcast:image provided artwork, seed classic imageUrl for older paths.
        if imageUrl == nil {
            imageUrl = PodcastImagesDisplay.preferredArtworkURL(channelImages)
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
            medium: channelMedium,
            itunesType: channelItunesType,
            updateFrequency: channelUpdateFrequency,
            isItunesComplete: feedIsItunesComplete,
            fundingUrl: fundingUrl,
            fundingLabel: fundingLabel,
            categories: Self.uniqueCategories(categoryTexts),
            isLocked: feedIsLocked,
            lockedOwner: lockedOwnerAttr,
            isBlocked: feedIsBlocked,
            podcastGuid: podcastGuid,
            people: channelPeople,
            trailers: channelTrailers,
            locations: channelLocations,
            socialInteracts: channelSocialInteracts,
            values: channelValues,
            liveItems: channelLiveItems,
            texts: channelTexts,
            licenses: channelLicenses,
            images: channelImages,
            podrollItems: channelPodrollItems,
            publisherItems: channelPublisherItems,
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
            itemPubDateIsUpdated = false
            itemDescription = nil
            enclosureUrl = nil
            enclosureType = nil
            enclosureLength = 0
            transcriptUrl = nil
            transcriptType = nil
            transcriptLanguage = nil
            transcriptPriority = 0
            itemChapters = []
            podcastIndexChapterUrl = nil
            podcastIndexChapterType = nil
            itemDurationSeconds = 0
            itemSeasonNumber = nil
            itemEpisodeNumber = nil
            itemEpisodeType = nil
            itemExplicitOverride = nil
            itemMedium = nil
            itemPeople = []
            itemLocations = []
            itemSocialInteracts = []
            itemValues = []
            itemAlternateEnclosures = []
            itemSoundbites = []
            capturingSoundbite = false
            pendingSoundbiteStart = nil
            pendingSoundbiteDuration = nil
            itemTexts = []
            capturingTxt = false
            pendingTxtPurpose = nil
            itemLicenses = []
            capturingLicense = false
            pendingLicenseUrl = nil
            itemImages = []
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
        case "images":
            // Podcast Index (deprecated): <podcast:images srcset="url 1500w, url 600w, …"/>
            // Channel and/or item. Absolute http(s) URLs + optional width descriptors. Cap ~10 later in display.
            // Do not eagerly download all variants — store URLs + widths only.
            if inLiveItem { break }
            if inPodroll || inPublisher { break }
            finishPodcastImagesSrcset(attributeDict["srcset"] ?? attributeDict["srcSet"], intoItem: inItem)
        case "image":
            // Three shapes share local name "image":
            // 1) podcast:image href="…" width="…" (and optional height/alt/purpose) — Podcasting 2.0
            // 2) itunes:image href="…" — classic artwork URL (prefer as feed.imageUrl when unset)
            // 3) RSS <image> wrapper with nested <url> — channel only (inImage)
            if inLiveItem { break }
            if inPodroll || inPublisher { break }
            let href = Self.nonEmptyAttr(attributeDict["href"] ?? attributeDict["url"])
            if let href {
                let ns = (namespaceURI ?? "").lowercased()
                let q = (qName ?? "").lowercased()
                let rawName = elementName.lowercased()
                // XMLParser often leaves prefixes on elementName when shouldProcessNamespaces is false.
                let looksPodcast = ns.contains("podcast")
                    || q.hasPrefix("podcast:")
                    || rawName.hasPrefix("podcast:")
                let widthRaw = attributeDict["width"]
                let heightRaw = attributeDict["height"]
                let alt = attributeDict["alt"]
                let purpose = attributeDict["purpose"]
                // podcast:image (ns / richer attrs) → variants list; itunes:image (href-only) → classic artwork only.
                if looksPodcast
                    || Self.nonEmptyAttr(widthRaw) != nil
                    || Self.nonEmptyAttr(heightRaw) != nil
                    || Self.nonEmptyAttr(alt) != nil
                    || Self.nonEmptyAttr(purpose) != nil
                    || Self.nonEmptyAttr(attributeDict["aspect-ratio"] ?? attributeDict["aspectRatio"]) != nil
                    || Self.nonEmptyAttr(attributeDict["type"]) != nil {
                    finishPodcastImage(
                        href: href,
                        widthRaw: widthRaw,
                        heightRaw: heightRaw,
                        alt: alt,
                        purpose: purpose,
                        intoItem: inItem
                    )
                }
                // itunes:image / podcast:image → seed classic imageUrl when unset (channel only).
                if !inItem, imageUrl == nil {
                    imageUrl = href
                }
            } else if !inItem {
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
            // Android Rss20: image MIME is artwork, never the playable file; only set media when
            // none exists yet. An image enclosure first would otherwise stick after the
            // media:content isDefault guard and drop a later playable audio/video URL.
            let rawEncUrl = (attributeDict["url"] ?? attributeDict["href"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let rawEncUrl, !rawEncUrl.isEmpty else { break }
            let encMime = attributeDict["type"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if encMime?.hasPrefix("image/") == true { break }
            guard enclosureUrl == nil else { break }
            enclosureUrl = rawEncUrl
            enclosureType = attributeDict["type"]
            enclosureLength = Int64(attributeDict["length"] ?? attributeDict["fileSize"] ?? "0") ?? 0
        case "content":
            if inLiveItem { break }
            // media:content / Atom content with a url. Image art must not become the
            // playable file, and a later non-default media:content must not replace
            // the RSS enclosure (or an earlier playable media URL). Same rule as
            // Android Media namespace: medium=image (unless MIME is audio/video) and
            // type=image/* are episode art; isDefault="true" may replace media.
            if let rawUrl = attributeDict["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawUrl.isEmpty {
                if Self.isImageMediaContent(attributeDict) {
                    break
                }
                let isDefault = attributeDict["isDefault"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "true"
                guard enclosureUrl == nil || isDefault else { break }
                enclosureUrl = rawUrl
                enclosureType = attributeDict["type"]
                if enclosureType == nil, attributeDict["medium"]?.lowercased() == "video" {
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
                    // Same Android Atom rules as RSS enclosure: non-empty URL, skip image/*,
                    // do not replace an already-chosen playable media URL.
                    let rawHref = href?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let rawHref, !rawHref.isEmpty else { break }
                    let linkMime = attributeDict["type"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if linkMime?.hasPrefix("image/") == true { break }
                    guard enclosureUrl == nil else { break }
                    enclosureUrl = rawHref
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
        case "block":
            // podcast:block (optional id=platform) and/or itunes:block — channel directory hide request.
            // Display-only — this app does not enforce (subscribe/play still allowed). Distinct from podcast:locked.
            if !inItem && !inLiveItem && !inPodroll && !inPublisher {
                capturingBlock = true
            }
        case "updatefrequency":
            // Podcast Index: <podcast:updateFrequency rrule="…" dtstart="…" complete="true|false">Weekly</podcast:updateFrequency>
            // Channel-level intended release schedule; display-only — does not change Keep updated / refresh.
            if !inItem && !inLiveItem && !inPodroll && !inPublisher {
                capturingUpdateFrequency = true
                pendingUpdateFrequencyRrule = Self.nonEmptyAttr(attributeDict["rrule"] ?? attributeDict["Rrule"])
                pendingUpdateFrequencyDtstart = Self.nonEmptyAttr(attributeDict["dtstart"] ?? attributeDict["Dtstart"])
                if let raw = attributeDict["complete"] ?? attributeDict["Complete"] {
                    pendingUpdateFrequencyComplete = PodcastUpdateFrequencyParsing.parseComplete(raw)
                } else {
                    pendingUpdateFrequencyComplete = nil
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
            // Podcast Index: <podcast:transcript url="…" type="application/json|text/vtt|application/srt" language="…"/>
            // Prefer JSON > VTT > SRT (AntennaPod Android TranscriptType priority).
            if inItem {
                let href = attributeDict["url"] ?? attributeDict["href"]
                let type = attributeDict["type"]
                let language = Self.nonEmptyAttr(attributeDict["language"] ?? attributeDict["lang"])
                if let href, !href.isEmpty {
                    let priority = TranscriptTypePreference.priority(forMime: type)
                    // Accept unknown/missing type at lowest priority so a lone URL still works.
                    let effective = priority > 0 ? priority : 1
                    if transcriptUrl == nil || effective > transcriptPriority {
                        transcriptUrl = href
                        transcriptType = type
                        transcriptLanguage = language
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
                    podcastIndexChapterType = Self.nonEmptyAttr(attributeDict["type"] ?? attributeDict["Type"])
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
                        title: (title?.isEmpty == false) ? title! : String(localized: "Chapter"),
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
        case "soundbite":
            // Podcast Index: <podcast:soundbite startTime="…" duration="…">optional title</podcast:soundbite>
            // Item-level only. startTime + duration required (seconds). Optional element text = title.
            // Display / seek-to-start via PlaybackService when current — no separate clip player.
            // Never invent soundbites.
            if inLiveItem { break }
            guard inItem else { break }
            capturingSoundbite = true
            if let rawStart = Self.nonEmptyAttr(attributeDict["startTime"] ?? attributeDict["starttime"]),
               let start = Double(rawStart), start.isFinite, start >= 0 {
                pendingSoundbiteStart = start
            } else {
                pendingSoundbiteStart = nil
            }
            if let rawDur = Self.nonEmptyAttr(attributeDict["duration"]),
               let dur = Double(rawDur), dur.isFinite, dur > 0 {
                pendingSoundbiteDuration = dur
            } else {
                pendingSoundbiteDuration = nil
            }
        case "podroll":
            // Podcast Index: <podcast:podroll>…</podcast:podroll> — channel-level creator recommendations.
            // Children: one or more <podcast:remoteItem …/>. Feed-provided only — never invent.
            // Display-only: Open / Copy / Subscribe-by-URL preview when feedUrl present.
            guard !inItem && !inLiveItem else { break }
            inPodroll = true
        case "publisher":
            // Podcast Index: <podcast:publisher>…</podcast:publisher> — channel link to publisher feed.
            // Children: typically exactly one <podcast:remoteItem …/>. Feed-provided only — never invent.
            // Display-only: Open / Copy / Subscribe-by-URL preview when feedUrl present.
            guard !inItem && !inLiveItem else { break }
            inPublisher = true
        case "remoteitem":
            // Podcast Index: <podcast:remoteItem feedGuid="…" feedUrl="…" title="…" medium="…" itemGuid="…"/>
            // Under podcast:podroll or podcast:publisher (channel). feedGuid required by namespace; feedUrl/title optional.
            // Never invent recommendations/publishers; do not resolve GUID via Podcast Index API in this beta.
            guard !inItem, !inLiveItem else { break }
            if inPublisher {
                finishPublisherRemoteItem(attributes: attributeDict)
            } else if inPodroll {
                finishRemoteItem(attributes: attributeDict)
            }
        case "txt":
            // Podcast Index: <podcast:txt purpose="…">text</podcast:txt>
            // Channel and/or item. Element text required; purpose optional — never invent.
            // Display-only: Copy / Open http(s). No Social / Matrix / special clients.
            if inLiveItem { break }
            if inPodroll || inPublisher { break }
            capturingTxt = true
            pendingTxtPurpose = Self.nonEmptyAttr(attributeDict["purpose"] ?? attributeDict["Purpose"])
        case "license":
            // Podcast Index: <podcast:license url="https://…">cc-by-4.0</podcast:license>
            // Channel and/or item. Text and/or url; display-only — no DRM enforcement.
            if inLiveItem { break }
            if inPodroll || inPublisher { break }
            capturingLicense = true
            pendingLicenseUrl = Self.nonEmptyAttr(attributeDict["url"] ?? attributeDict["href"])
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
                // Only the item's own title. A nested media:title (inside media:content or
                // media:group) or Atom source title would rename every episode, and an
                // empty itunes:title would blank it.
                let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2].lowercased() : ""
                if (parent == "item" || parent == "entry"), !text.isEmpty {
                    itemTitle = text
                }
            case "link":
                if itemLink == nil, !text.isEmpty {
                    itemLink = text
                }
            case "guid", "id":
                itemGuid = text
            case "pubdate", "published":
                itemPubDate = text
                itemPubDateIsUpdated = false
            case "updated":
                // Atom lists <updated> after <published> and bumps it on every edit.
                // Use it only when the entry has no publish date of its own.
                if itemPubDate == nil || itemPubDateIsUpdated {
                    itemPubDate = text
                    itemPubDateIsUpdated = true
                }
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
                // itunes:episodeType — store non-empty raw (full/trailer/bonus/…); never invent. Display localizes known.
                if let t = ItunesSeasonEpisodeParsing.nonEmptyEpisodeType(from: text) {
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
            case "soundbite":
                finishSoundbite(text: text)
            case "txt":
                finishTxt(text: text, intoItem: true)
            case "license":
                finishLicense(text: text, intoItem: true)
            case "medium":
                // Podcast Index <podcast:medium>…</podcast:medium> on item — store raw string; never invent/remap.
                // Distinct from media:content@medium and podcast:remoteItem medium attribute.
                if !text.isEmpty {
                    itemMedium = text
                }
            case "item", "entry":
                let sorted = itemChapters.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
                let episode = PodcastEpisode(
                    id: stableEpisodeIdentity(),
                    title: itemTitle ?? "Episode",
                    link: itemLink,
                    pubDateEpochMs: FeedDateParsing.epochMs(from: itemPubDate),
                    downloadUrl: enclosureUrl,
                    mimeType: enclosureType,
                    size: enclosureLength,
                    transcriptUrl: transcriptUrl,
                    transcriptType: transcriptType,
                    transcriptLanguage: transcriptLanguage,
                    chapters: sorted,
                    podcastIndexChapterUrl: podcastIndexChapterUrl,
                    podcastIndexChapterType: podcastIndexChapterType,
                    descriptionText: itemDescription,
                    durationSeconds: itemDurationSeconds,
                    seasonNumber: itemSeasonNumber,
                    episodeNumber: itemEpisodeNumber,
                    episodeType: itemEpisodeType,
                    isExplicit: itemExplicitOverride ?? feedIsExplicit,
                    medium: itemMedium,
                    people: itemPeople,
                    locations: itemLocations,
                    socialInteracts: itemSocialInteracts,
                    values: itemValues,
                    alternateEnclosures: itemAlternateEnclosures,
                    soundbites: itemSoundbites,
                    texts: itemTexts,
                    licenses: itemLicenses,
                    images: itemImages
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
            case "block":
                // podcast:block / itunes:block — yes/true → directory block metadata (OR across tags; no does not clear a prior yes).
                // Optional podcast:block id=platform is ignored for the single isBlocked flag (display-only).
                if capturingBlock {
                    if let flagged = PodcastBlockParsing.parse(text), flagged {
                        feedIsBlocked = true
                    }
                    capturingBlock = false
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
            case "medium":
                // Podcast Index <podcast:medium>…</podcast:medium> on channel — store raw string; never invent/remap.
                // Distinct from media:content@medium and podcast:remoteItem medium attribute (podroll/publisher).
                // Skip when inside podroll/publisher (remoteItem is attribute-only) / liveItem.
                if inPodroll || inPublisher { break }
                if !text.isEmpty {
                    channelMedium = text
                }
            case "type":
                // itunes:type — episodic | serial (Apple Podcasts). Channel only; store raw trimmed; never invent. Capsule display-only; Serial→Oldest-first is nil-only FeedSettings heuristic.
                // Distinct from enclosure@type / media type / podcast:value@type attributes (those are attributes, not elements).
                // Does not change default episode sort (display-only).
                if inPodroll || inPublisher || inLiveItem { break }
                if let raw = ItunesTypeParsing.nonEmptyRaw(text) {
                    channelItunesType = raw
                }
            case "updatefrequency":
                // podcast:updateFrequency — free-form text + optional rrule/dtstart/complete. Channel only.
                // Display-only — never invent schedule; does not change Keep updated / refresh.
                if capturingUpdateFrequency {
                    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let uf = PodcastUpdateFrequency(
                        text: body.isEmpty ? nil : body,
                        rrule: pendingUpdateFrequencyRrule,
                        dtstart: pendingUpdateFrequencyDtstart,
                        complete: pendingUpdateFrequencyComplete
                    )
                    if uf.hasContent {
                        channelUpdateFrequency = uf
                    }
                    capturingUpdateFrequency = false
                    pendingUpdateFrequencyRrule = nil
                    pendingUpdateFrequencyDtstart = nil
                    pendingUpdateFrequencyComplete = nil
                }
            case "complete":
                // itunes:complete — Yes/yes/true → complete (Apple Podcasts). Channel only.
                // Distinct from podcast:updateFrequency@complete (attribute on updateFrequency element).
                // Display-only — does not change Keep updated / refresh.
                if inItem || inLiveItem || inPodroll || inPublisher { break }
                if let flagged = ItunesCompleteParsing.parse(text) {
                    feedIsItunesComplete = flagged
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
            case "txt":
                finishTxt(text: text, intoItem: false)
            case "license":
                finishLicense(text: text, intoItem: false)
            case "podroll":
                inPodroll = false
            case "publisher":
                inPublisher = false
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

    /// Finish podcast:alternateEnclosure — append when type + ≥1 source; UI Play http(s) via preferredMediaURL.
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


    /// Finish podcast:soundbite — append when startTime (≥0) + duration (>0); optional title text.
    /// Display / seek-to-start only — never invent; no separate clip player.
    private func finishSoundbite(text: String) {
        defer {
            capturingSoundbite = false
            pendingSoundbiteStart = nil
            pendingSoundbiteDuration = nil
        }
        guard capturingSoundbite, inItem else { return }
        guard let start = pendingSoundbiteStart, start.isFinite, start >= 0 else { return }
        guard let duration = pendingSoundbiteDuration, duration.isFinite, duration > 0 else { return }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        itemSoundbites.append(
            PodcastSoundbite(
                startTimeSeconds: start,
                durationSeconds: duration,
                title: title.isEmpty ? nil : title
            )
        )
    }

    /// Finish podcast:remoteItem under podroll — append when feedGuid and/or feedUrl present; never invent.
    /// Display-only Open / Copy / Subscribe preview — no Podcast Index GUID resolution / no auto-subscribe.
    private func finishRemoteItem(attributes attributeDict: [String: String]) {
        guard inPodroll, !inItem, !inLiveItem else { return }
        let feedGuid = Self.nonEmptyAttr(attributeDict["feedGuid"] ?? attributeDict["feedguid"])
        let feedUrl = Self.nonEmptyAttr(attributeDict["feedUrl"] ?? attributeDict["feedurl"] ?? attributeDict["url"])
        let title = Self.nonEmptyAttr(attributeDict["title"])
        let medium = Self.nonEmptyAttr(attributeDict["medium"])
        let itemGuid = Self.nonEmptyAttr(attributeDict["itemGuid"] ?? attributeDict["itemguid"])
        guard feedGuid != nil || feedUrl != nil else { return }
        channelPodrollItems.append(
            PodcastRemoteItem(
                feedGuid: feedGuid,
                feedUrl: feedUrl,
                title: title,
                medium: medium,
                itemGuid: itemGuid
            )
        )
    }


    /// Finish podcast:remoteItem under publisher — append when feedGuid and/or feedUrl present; never invent.
    /// Display-only Open / Copy / Subscribe preview — no Podcast Index GUID resolution / no auto-subscribe.
    private func finishPublisherRemoteItem(attributes attributeDict: [String: String]) {
        guard inPublisher, !inItem, !inLiveItem else { return }
        let feedGuid = Self.nonEmptyAttr(attributeDict["feedGuid"] ?? attributeDict["feedguid"])
        let feedUrl = Self.nonEmptyAttr(attributeDict["feedUrl"] ?? attributeDict["feedurl"] ?? attributeDict["url"])
        let title = Self.nonEmptyAttr(attributeDict["title"])
        let medium = Self.nonEmptyAttr(attributeDict["medium"])
        let itemGuid = Self.nonEmptyAttr(attributeDict["itemGuid"] ?? attributeDict["itemguid"])
        guard feedGuid != nil || feedUrl != nil else { return }
        channelPublisherItems.append(
            PodcastRemoteItem(
                feedGuid: feedGuid,
                feedUrl: feedUrl,
                title: title,
                medium: medium,
                itemGuid: itemGuid
            )
        )
    }

    /// Finish podcast:txt — append when element text non-empty; optional purpose as provided.
    /// Display-only Copy / Open http(s) — never invent; no Social / Matrix clients.
    private func finishTxt(text: String, intoItem: Bool) {
        defer {
            capturingTxt = false
            pendingTxtPurpose = nil
        }
        guard capturingTxt else { return }
        if intoItem {
            guard inItem else { return }
        } else {
            guard !inItem else { return }
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let entry = PodcastTxt(purpose: pendingTxtPurpose, text: body)
        if intoItem {
            itemTexts.append(entry)
        } else {
            channelTexts.append(entry)
        }
    }

    /// Finish podcast:license — append when text and/or http(s) url present; never invent; no DRM.
    private func finishLicense(text: String, intoItem: Bool) {
        defer {
            capturingLicense = false
            pendingLicenseUrl = nil
        }
        guard capturingLicense else { return }
        if intoItem {
            guard inItem else { return }
        } else {
            guard !inItem else { return }
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlAttr = pendingLicenseUrl
        let openable: Bool = {
            guard let urlAttr, let u = URL(string: urlAttr) else { return false }
            let scheme = u.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }()
        guard !body.isEmpty || openable else { return }
        let entry = PodcastLicense(url: urlAttr, text: body)
        if intoItem {
            itemLicenses.append(entry)
        } else {
            channelLicenses.append(entry)
        }
    }


    /// Finish podcast:images srcset — parse "url Nw, url Nw, …" into variants (absolute http(s) preferred).
    /// Cap applied at parse/display (~10). Never invent URLs; do not download variants here.
    private func finishPodcastImagesSrcset(_ srcset: String?, intoItem: Bool) {
        guard let srcset else { return }
        let trimmed = srcset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed.split(separator: ",")
        for part in parts {
            let tokens = part.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            guard let urlToken = tokens.first, !urlToken.isEmpty else { continue }
            var width: Int?
            if tokens.count >= 2 {
                let desc = tokens[1].lowercased()
                if desc.hasSuffix("w"), let n = Int(desc.dropLast()), n > 0 {
                    width = n
                }
                // Density descriptors (1x/2x) are ignored for width — never invent a pixel width.
            }
            appendPodcastImageVariant(
                PodcastImageVariant(url: urlToken, width: width),
                intoItem: intoItem
            )
        }
    }

    /// Finish podcast:image (href) or itunes:image (href) — store as variant; optional width/height/alt/purpose.
    private func finishPodcastImage(
        href: String,
        widthRaw: String?,
        heightRaw: String?,
        alt: String?,
        purpose: String?,
        intoItem: Bool
    ) {
        let width = Self.positiveIntAttr(widthRaw)
        let height = Self.positiveIntAttr(heightRaw)
        appendPodcastImageVariant(
            PodcastImageVariant(
                url: href,
                width: width,
                height: height,
                alt: Self.nonEmptyAttr(alt),
                purpose: Self.nonEmptyAttr(purpose)
            ),
            intoItem: intoItem
        )
    }

    private func appendPodcastImageVariant(_ variant: PodcastImageVariant, intoItem: Bool) {
        // Soft parse-time cap so pathological feeds cannot balloon library JSON — display cap matches.
        let cap = PodcastImagesDisplay.displayCap
        if intoItem {
            guard inItem else { return }
            guard itemImages.count < cap else { return }
            itemImages.append(variant)
        } else {
            guard !inItem else { return }
            guard channelImages.count < cap else { return }
            channelImages.append(variant)
        }
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

    /// MRSS `media:content` that is episode art, not a playable enclosure.
    /// `medium=image` is art unless the MIME is audio/video (some feeds mislabel the
    /// audio file as an image). `type=image/*` is art unless medium is audio or video.
    fileprivate static func isImageMediaContent(_ attributeDict: [String: String]) -> Bool {
        let medium = attributeDict["medium"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mime = attributeDict["type"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if medium == "audio" || medium == "video" {
            return false
        }
        let audioOrVideoMime = mime?.hasPrefix("audio/") == true || mime?.hasPrefix("video/") == true
        if medium == "image" {
            return !audioOrVideoMime
        }
        return mime?.hasPrefix("image/") == true
    }

    /// Identity that survives the next refresh.
    /// A fresh UUID made items with no guid and no link look new on every parse
    /// (new-episode banner, Inbox, add-to-queue). Empty guid/link is not an id.
    /// Enclosure URL, else title and publish date; UUID only when nothing else exists.
    private func stableEpisodeIdentity() -> String {
        if let id = Self.nonEmptyAttr(itemGuid) { return id }
        if let id = Self.nonEmptyAttr(itemLink) { return id }
        if let id = Self.nonEmptyAttr(enclosureUrl) { return id }
        let title = (itemTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = (itemPubDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty || !date.isEmpty {
            return "\(title)|\(date)"
        }
        return UUID().uuidString
    }

    /// Trimmed non-empty attribute value, or nil.
    fileprivate static func nonEmptyAttr(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate static func positiveIntAttr(_ raw: String?) -> Int? {
        guard let raw = nonEmptyAttr(raw), let n = Int(raw), n > 0 else { return nil }
        return n
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

    /// Non-empty trimmed raw `itunes:episodeType` text, or `nil` when blank.
    /// Stores as provided (full/trailer/bonus/unknown); never invents. Display localizes known values.
    static func nonEmptyEpisodeType(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Canonical lowercase `full` / `trailer` / `bonus`, or `nil` when absent/unknown (caller may still store raw).
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

/// Podcast Index `podcast:updateFrequency` `complete` attribute.
/// Spec: boolean. Accept true/yes / false/no. Unknown/empty → nil (do not invent).
enum PodcastUpdateFrequencyParsing {
    static func parseComplete(_ raw: String) -> Bool? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }
}

/// Channel `itunes:type` from feed text nodes (Apple Podcasts: episodic / serial).
/// Stores non-empty raw trimmed text; never invents. Display localizes known values; unknown → show raw or hide.
/// Capsule is display-only; Serial → Oldest first is a separate nil-only FeedSettings heuristic.
enum ItunesTypeParsing {
    /// Non-empty trimmed raw `itunes:type` text, or `nil` when blank.
    static func nonEmptyRaw(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Canonical lowercase `episodic` / `serial`, or `nil` when absent/unknown (caller may still store raw).
    static func canonical(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "episodic", "serial":
            return trimmed
        default:
            return nil
        }
    }
}

/// Apple Podcasts `itunes:complete` channel text nodes.
/// Spec: `Yes` / `No`. Also accept `true` / `false` / lowercase yes/no. Unknown/empty → nil (do not invent).
/// Distinct from `podcast:updateFrequency` `complete` attribute (`PodcastUpdateFrequencyParsing.parseComplete`).
enum ItunesCompleteParsing {
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

/// Channel `podcast:block` / `itunes:block` text nodes (directory hide request).
/// Spec: `yes` / `no` (Apple often `Yes`). Also accept `true` / `false`. Unknown/empty → nil (do not invent).
/// Display-only — directories may honor this; this app does not enforce subscribe/play.
enum PodcastBlockParsing {
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
