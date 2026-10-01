import Foundation

/// Lightweight HTML → plain text for episode shownotes (beta).
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
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

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
}
