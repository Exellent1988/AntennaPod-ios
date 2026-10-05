import Foundation

/// Lightweight HTML → plain text for episode shownotes / feed descriptions (beta).
/// Not a full HTML renderer — strips tags, decodes common entities, normalizes whitespace.
enum HTMLTextStripping {
    static func plainText(from html: String) -> String {
        var out = html
        // Block-ish tags → paragraph breaks before stripping.
        let blockPattern = #"(?i)</?(p|div|br|li|h[1-6]|tr|blockquote)[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: blockPattern) {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: "\n"
            )
        }
        if let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }
        out = out
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        // WordPress-style shownotes use numeric entities (&#8217; &#8211; &#x2019;),
        // which were shown raw. &amp; goes last so "&amp;lt;" stays the text "&lt;".
        out = decodeNumericEntities(out)
            .replacingOccurrences(of: "&amp;", with: "&")

        // Collapse runs of blank lines / spaces.
        if let regex = try? NSRegularExpression(pattern: #"[ \t]+\n"#) {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: "\n"
            )
        }
        if let regex = try? NSRegularExpression(pattern: #"\n{3,}"#) {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: "\n\n"
            )
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `&#NNNN;` and `&#xHHHH;` → the character. Invalid code points stay as written.
    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#"),
              let regex = try? NSRegularExpression(pattern: #"&#([xX][0-9a-fA-F]{1,6}|[0-9]{1,7});"#)
        else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let body = ns.substring(with: match.range(at: 1))
            let value: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body)
            }
            if let value, let scalar = Unicode.Scalar(value) {
                result.unicodeScalars.append(scalar)
            } else {
                result += ns.substring(with: match.range)
            }
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
