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
            if inItem, transcriptUrl == nil {
                transcriptUrl = attributeDict["url"]
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
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
                if itemDescription == nil, !text.isEmpty {
                    itemDescription = text
                }
            case "item", "entry":
                let episode = PodcastEpisode(
                    id: itemGuid ?? itemLink ?? UUID().uuidString,
                    title: itemTitle ?? "Episode",
                    link: itemLink,
                    pubDateEpochMs: FeedDateParsing.epochMs(from: itemPubDate),
                    downloadUrl: enclosureUrl,
                    mimeType: enclosureType,
                    size: enclosureLength,
                    transcriptUrl: transcriptUrl
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
