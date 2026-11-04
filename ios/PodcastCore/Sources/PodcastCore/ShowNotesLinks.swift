import Foundation

/// Android `ShownotesCleaner`: tappable timestamps (h:mm:ss / mm:ss, only below the known duration)
/// and links (bare http(s) URLs and `<a href>` anchor texts) in plain-text show notes.
public enum ShowNotesLinks {
    public enum Kind: Equatable, Sendable {
        case url(String)
        case timestamp(seconds: Int)
    }

    public struct Run: Equatable, Sendable {
        public var text: String
        public var kind: Kind?
        public init(text: String, kind: Kind? = nil) { self.text = text; self.kind = kind }
    }

    /// `<a href="http…">text</a>` pairs (http(s) only, tags in the text stripped).
    public static func anchors(inHTML html: String) -> [(text: String, href: String)] {
        guard let re = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a\s*>"#) else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let href = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard href.lowercased().hasPrefix("http://") || href.lowercased().hasPrefix("https://") else { return nil }
            let text = ns.substring(with: m.range(at: 2))
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.count >= 2 ? (text, href) : nil
        }
    }

    /// Seconds for `h:mm:ss` or `mm:ss`; nil when a field is out of range.
    public static func timestampSeconds(_ s: String) -> Int? {
        let parts = s.split(separator: ":").map { Int($0) }
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        let p = parts.map { $0! }
        let sec = p[p.count - 1], min = p[p.count - 2], hours = p.count == 3 ? p[0] : 0
        guard sec < 60, (p.count == 2 || min < 60) else { return nil }
        return hours * 3600 + min * 60 + sec
    }

    public static func runs(_ text: String, anchors: [(text: String, href: String)] = [], durationSeconds: Double? = nil) -> [Run] {
        let ns = text as NSString
        var found: [(NSRange, Kind)] = []
        if let re = try? NSRegularExpression(pattern: #"https?://[^\s<>"]+"#, options: .caseInsensitive) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var r = m.range
                while r.length > 0, let last = ns.substring(with: NSRange(location: r.location + r.length - 1, length: 1)).first,
                      ".,;:!?)]'".contains(last) { r.length -= 1 }
                found.append((r, .url(ns.substring(with: r))))
            }
        }
        for a in anchors {
            let r = ns.range(of: a.text)
            if r.location != NSNotFound { found.append((r, .url(a.href))) }
        }
        if let re = try? NSRegularExpression(pattern: #"(?<![\d:])(?:\d{1,2}:)?\d{1,2}:\d{2}(?![\d:])"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let secs = timestampSeconds(ns.substring(with: m.range)) else { continue }
                if let d = durationSeconds, d > 0, Double(secs) >= d { continue }
                found.append((m.range, .timestamp(seconds: secs)))
            }
        }
        // Earlier wins; on equal start, links (collected first) beat timestamps. Overlaps dropped.
        var chosen: [(NSRange, Kind)] = []
        for item in found.enumerated().sorted(by: { ($0.element.0.location, $0.offset) < ($1.element.0.location, $1.offset) }).map(\.element) {
            if let last = chosen.last, item.0.location < last.0.location + last.0.length { continue }
            chosen.append(item)
        }
        var out: [Run] = []
        var cursor = 0
        for (r, kind) in chosen {
            if r.location > cursor { out.append(Run(text: ns.substring(with: NSRange(location: cursor, length: r.location - cursor)))) }
            out.append(Run(text: ns.substring(with: r), kind: kind))
            cursor = r.location + r.length
        }
        if cursor < ns.length { out.append(Run(text: ns.substring(from: cursor))) }
        return out
    }
}
