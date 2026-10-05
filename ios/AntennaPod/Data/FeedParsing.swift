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
