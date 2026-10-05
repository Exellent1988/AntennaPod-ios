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
