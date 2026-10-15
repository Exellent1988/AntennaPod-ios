import Foundation

/// Android `ChapterReader` (ID3v2 `CHAP` frames) for MP3 podcasts. AVFoundation does not surface
/// ID3 CHAP on iOS, so this walks the tag bytes itself. Pure Swift; no I/O.
///
/// Supported: ID3v2.3 and v2.4 tags, `CHAP` with `TIT2` title, `WXXX` link, `APIC` embedded image
/// (bytes) or `-->` image URL. Extended header skipped. Unknown frames are ignored.
public enum ID3ChapterParser {
    public struct Chapter: Equatable, Sendable {
        public var elementId: String
        public var startSeconds: Double
        public var title: String?
        public var url: String?
        public var imageURL: String?
        public var imageData: Data?
        public var imageMimeType: String?
    }

    /// Bytes needed to parse the whole tag (header + body), or nil when `header` is not an ID3v2 tag.
    public static func tagLength(header: Data) -> Int? {
        let h = [UInt8](header.prefix(10))
        guard h.count == 10, h[0] == 0x49, h[1] == 0x44, h[2] == 0x33, h[3] == 3 || h[3] == 4 else { return nil }
        return 10 + synchsafe(h[6], h[7], h[8], h[9])
    }

    /// Chapters sorted by start time, duplicates by start dropped. `[]` for no tag / no CHAP.
    public static func chapters(in data: Data) -> [Chapter] {
        let b = [UInt8](data)
        guard let total = tagLength(header: data) else { return [] }
        let version = b[3]
        let flags = b[5]
        let end = min(total, b.count)
        var pos = 10
        if flags & 0x40 != 0, pos + 4 <= end { // extended header
            let size = version == 4 ? synchsafe(b[pos], b[pos + 1], b[pos + 2], b[pos + 3])
                                    : be32(b, pos) + 4
            pos += size
        }
        var result: [Chapter] = []
        for frame in frames(b, from: pos, to: end, version: version) where frame.id == "CHAP" {
            if let c = parseChap(b, frame.body, version: version) { result.append(c) }
        }
        var seen = Set<Double>()
        return result.sorted { $0.startSeconds < $1.startSeconds }.filter { seen.insert($0.startSeconds).inserted }
    }

    // MARK: Internals

    private struct Frame { var id: String; var body: Range<Int> }

    private static func frames(_ b: [UInt8], from start: Int, to end: Int, version: UInt8) -> [Frame] {
        var out: [Frame] = []
        var pos = start
        while pos + 10 <= end {
            let idBytes = b[pos..<pos + 4]
            guard idBytes.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) }) else { break } // padding
            let id = String(decoding: idBytes, as: UTF8.self)
            let size = version == 4 ? synchsafe(b[pos + 4], b[pos + 5], b[pos + 6], b[pos + 7]) : be32(b, pos + 4)
            let bodyStart = pos + 10
            guard size >= 0, bodyStart + size <= end else { break }
            out.append(Frame(id: id, body: bodyStart..<bodyStart + size))
            pos = bodyStart + size
        }
        return out
    }

    private static func parseChap(_ b: [UInt8], _ r: Range<Int>, version: UInt8) -> Chapter? {
        guard let nul = b[r].firstIndex(of: 0) else { return nil }
        let elementId = String(decoding: b[r.lowerBound..<nul], as: UTF8.self)
        let t = nul + 1
        guard t + 16 <= r.upperBound else { return nil }
        let startMs = be32(b, t)
        var chapter = Chapter(elementId: elementId, startSeconds: Double(startMs) / 1000)
        for sub in frames(b, from: t + 16, to: r.upperBound, version: version) {
            switch sub.id {
            case "TIT2": chapter.title = text(b, sub.body)
            case "WXXX": chapter.url = wxxx(b, sub.body)
            case "APIC": apic(b, sub.body, into: &chapter)
            default: break
            }
        }
        return chapter
    }

    private static func text(_ b: [UInt8], _ r: Range<Int>) -> String? {
        guard r.count > 1 else { return nil }
        let s = decode(Array(b[(r.lowerBound + 1)..<r.upperBound]), encoding: b[r.lowerBound])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return s.isEmpty ? nil : s
    }

    private static func wxxx(_ b: [UInt8], _ r: Range<Int>) -> String? {
        guard r.count > 1 else { return nil }
        let enc = b[r.lowerBound]
        let afterDesc = skipTerminated(b, from: r.lowerBound + 1, to: r.upperBound, encoding: enc)
        let s = String(decoding: b[afterDesc..<r.upperBound].filter { $0 != 0 }, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    private static func apic(_ b: [UInt8], _ r: Range<Int>, into c: inout Chapter) {
        guard r.count > 2 else { return }
        let enc = b[r.lowerBound]
        guard let mimeEnd = b[(r.lowerBound + 1)..<r.upperBound].firstIndex(of: 0) else { return }
        let mime = String(decoding: b[(r.lowerBound + 1)..<mimeEnd], as: UTF8.self)
        let afterType = mimeEnd + 2 // NUL + picture type
        guard afterType <= r.upperBound else { return }
        let dataStart = skipTerminated(b, from: afterType, to: r.upperBound, encoding: enc)
        let payload = Data(b[dataStart..<r.upperBound])
        if mime == "-->" {
            let url = String(decoding: payload.filter { $0 != 0 }, as: UTF8.self)
            if !url.isEmpty { c.imageURL = url }
        } else if !payload.isEmpty {
            c.imageData = payload
            c.imageMimeType = mime.isEmpty ? "image/jpeg" : mime
        }
    }

    /// Index after a string terminated per encoding (1 NUL for 0/3, 2 NULs aligned for 1/2).
    private static func skipTerminated(_ b: [UInt8], from: Int, to: Int, encoding: UInt8) -> Int {
        var i = from
        if encoding == 1 || encoding == 2 {
            while i + 1 < to { if b[i] == 0 && b[i + 1] == 0 { return i + 2 }; i += 2 }
            return to
        }
        while i < to { if b[i] == 0 { return i + 1 }; i += 1 }
        return to
    }

    private static func decode(_ bytes: [UInt8], encoding: UInt8) -> String {
        switch encoding {
        case 1: return String(data: Data(bytes), encoding: .utf16) ?? ""
        case 2: return String(data: Data(bytes), encoding: .utf16BigEndian) ?? ""
        case 3: return String(decoding: bytes, as: UTF8.self)
        default: return String(bytes.map { Character(Unicode.Scalar($0)) })
        }
    }

    private static func synchsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        Int(a & 0x7F) << 21 | Int(b & 0x7F) << 14 | Int(c & 0x7F) << 7 | Int(d & 0x7F)
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
}

/// Builds ID3v2 tags with CHAP frames — used by tests and fixture generation.
public enum ID3ChapterTagBuilder {
    public struct Input {
        public var title: String
        public var startMs: UInt32
        public var endMs: UInt32
        public var url: String?
        public var image: Data?
        public init(title: String, startMs: UInt32, endMs: UInt32, url: String? = nil, image: Data? = nil) {
            self.title = title; self.startMs = startMs; self.endMs = endMs; self.url = url; self.image = image
        }
    }

    public static func tag(_ chapters: [Input], version: UInt8 = 3, titleEncoding: UInt8 = 3) -> Data {
        var body: [UInt8] = []
        for (i, c) in chapters.enumerated() {
            var chap: [UInt8] = Array("ch\(i)".utf8) + [0]
            chap += be(c.startMs) + be(c.endMs) + be(0xFFFF_FFFF) + be(0xFFFF_FFFF)
            let titleBytes: [UInt8]
            switch titleEncoding {
            case 1: titleBytes = [0xFF, 0xFE] + c.title.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
            case 0: titleBytes = c.title.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
            default: titleBytes = Array(c.title.utf8)
            }
            chap += frame("TIT2", [titleEncoding] + titleBytes, version)
            if let url = c.url { chap += frame("WXXX", [0, 0] + Array(url.utf8), version) }
            if let img = c.image { chap += frame("APIC", [0] + Array("image/png".utf8) + [0, 0, 0] + [UInt8](img), version) }
            body += frame("CHAP", chap, version)
        }
        body += [UInt8](repeating: 0, count: 16) // padding
        return Data([0x49, 0x44, 0x33, version, 0, 0] + synchsafe(body.count) + body)
    }

    private static func frame(_ id: String, _ body: [UInt8], _ v: UInt8) -> [UInt8] {
        Array(id.utf8) + (v == 4 ? synchsafe(body.count) : be(UInt32(body.count))) + [0, 0] + body
    }
    private static func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private static func synchsafe(_ n: Int) -> [UInt8] {
        [UInt8(n >> 21 & 0x7F), UInt8(n >> 14 & 0x7F), UInt8(n >> 7 & 0x7F), UInt8(n & 0x7F)]
    }
}

/// iOS Now Playing chapter fields (MPNowPlayingInfoPropertyChapterNumber / Count).
public enum ChapterNowPlaying {
    /// 0-based index of the chapter active at `position` (last start ≤ position), or nil before the first.
    public static func index(starts: [Double], at position: Double) -> Int? {
        guard position.isFinite else { return nil }
        var found: Int?
        for (i, s) in starts.enumerated() where s <= position + 0.001 { found = i }
        return found
    }
}
