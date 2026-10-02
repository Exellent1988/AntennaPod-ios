import Foundation

enum OpmlReaderError: LocalizedError {
    case empty
    case parseFailed(String)
    case notOpml

    var errorDescription: String? {
        switch self {
        case .empty: return String(localized: "OPML file is empty")
        case .parseFailed(let m): return m
        case .notOpml: return String(localized: "Not a valid OPML document")
        }
    }
}

enum OpmlReader {
    static func parse(data: Data) throws -> [OpmlOutline] {
        guard !data.isEmpty else { throw OpmlReaderError.empty }
        let parser = OpmlXMLParser(data: data)
        return try parser.parse()
    }

    static func parse(xml: String) throws -> [OpmlOutline] {
        guard let data = xml.data(using: .utf8) else { throw OpmlReaderError.empty }
        return try parse(data: data)
    }
}

private final class OpmlXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var outlines: [OpmlOutline] = []
    private var seenOpml = false
    private var parseError: Error?

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.shouldProcessNamespaces = false
    }

    func parse() throws -> [OpmlOutline] {
        guard parser.parse() else {
            throw OpmlReaderError.parseFailed(parser.parserError?.localizedDescription ?? "XML parse failed")
        }
        if let parseError {
            throw parseError
        }
        guard seenOpml else {
            throw OpmlReaderError.notOpml
        }
        return outlines
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = localName(elementName).lowercased()
        if local == "opml" {
            seenOpml = true
            return
        }
        guard seenOpml, local == "outline" else { return }

        let xmlUrl = attributeValue(attributeDict, keys: ["xmlUrl", "xmlurl", "XMLURL"])
        guard let xmlUrl, !xmlUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Category / folder outlines have no xmlUrl — skip (nested feeds still visited).
            return
        }

        let title = attributeValue(attributeDict, keys: ["title", "Title"])
        let text = attributeValue(attributeDict, keys: ["text", "Text"])
        let display: String
        if let title, !title.isEmpty {
            display = title
        } else if let text, !text.isEmpty {
            display = text
        } else {
            display = xmlUrl
        }

        let htmlUrl = attributeValue(attributeDict, keys: ["htmlUrl", "htmlurl", "HTMLURL"])
        let type = attributeValue(attributeDict, keys: ["type", "Type"])

        outlines.append(
            OpmlOutline(
                text: display,
                xmlUrl: xmlUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                htmlUrl: htmlUrl,
                type: type
            )
        )
    }

    private func attributeValue(_ dict: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let v = dict[key], !v.isEmpty { return v }
            // Case-insensitive fallback
            if let pair = dict.first(where: { $0.key.lowercased() == key.lowercased() }), !pair.value.isEmpty {
                return pair.value
            }
        }
        return nil
    }

    private func localName(_ name: String) -> String {
        if let idx = name.lastIndex(of: ":") {
            return String(name[name.index(after: idx)...])
        }
        return name
    }
}
