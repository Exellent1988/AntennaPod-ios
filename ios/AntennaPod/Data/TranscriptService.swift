import Foundation
import CryptoKit

/// One cue / segment from a remote transcript (VTT / SRT / Podcast Index JSON).
struct TranscriptCue: Identifiable, Hashable {
    var id: String { "\(startTimeSeconds)|\(text.prefix(40))" }
    /// Start offset from episode beginning (seconds).
    var startTimeSeconds: Double
    var endTimeSeconds: Double?
    var text: String
    var speaker: String?
}

/// Parsed (or plain-text fallback) transcript for the full-player sheet.
struct ParsedTranscript: Hashable {
    var cues: [TranscriptCue]
    /// When cues could not be parsed — best-effort full body for scrolling reading.
    var plainText: String?
    var sourceURL: String
    var mimeType: String?

    var isEmpty: Bool {
        cues.isEmpty && (plainText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasSeekableCues: Bool { !cues.isEmpty }
}

/// Fetches feed-provided transcript URLs and extracts cues / plain text.
/// Honest: only when the feed supplies a URL — no Whisper / on-device STT.
enum TranscriptService {
    private static let memoryLock = NSLock()
    private static var memoryCache: [String: ParsedTranscript] = [:]
    private static let maxMemoryEntries = 12

    static func cached(forURL urlString: String) -> ParsedTranscript? {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        if let hit = memoryCache[urlString] { return hit }
        return loadDisk(urlString: urlString)
    }

    static func fetch(
        urlString: String,
        mimeHint: String?
    ) async throws -> ParsedTranscript {
        if let hit = cached(forURL: urlString) {
            return hit
        }
        guard let url = URL(string: urlString) else {
            throw FeedParsingError.message(String(localized: "Invalid transcript URL"))
        }
        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        let (data, response) = try await AppURLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FeedParsingError.message(String(localized: "Transcript HTTP \(http.statusCode)"))
        }
        let mime = mimeHint
            ?? (response as? HTTPURLResponse)?.mimeType
            ?? guessMime(from: urlString)
        let body = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let parsed = TranscriptParser.parse(body: body, mimeType: mime, sourceURL: urlString)
        store(parsed)
        return parsed
    }

    private static func store(_ transcript: ParsedTranscript) {
        memoryLock.lock()
        memoryCache[transcript.sourceURL] = transcript
        if memoryCache.count > maxMemoryEntries {
            // Drop an arbitrary older entry (session cache; not LRU-critical).
            if let first = memoryCache.keys.first(where: { $0 != transcript.sourceURL }) {
                memoryCache.removeValue(forKey: first)
            }
        }
        memoryLock.unlock()
        saveDisk(transcript)
    }

    private static func cacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func diskKey(for urlString: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadDisk(urlString: String) -> ParsedTranscript? {
        guard let dir = cacheDirectory() else { return nil }
        let file = dir.appendingPathComponent(diskKey(for: urlString)).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(DiskTranscript.self, from: data) else {
            return nil
        }
        let parsed = decoded.asParsed
        memoryLock.lock()
        memoryCache[urlString] = parsed
        memoryLock.unlock()
        return parsed
    }

    private static func saveDisk(_ transcript: ParsedTranscript) {
        guard let dir = cacheDirectory() else { return }
        let file = dir.appendingPathComponent(diskKey(for: transcript.sourceURL)).appendingPathExtension("json")
        let disk = DiskTranscript(from: transcript)
        guard let data = try? JSONEncoder().encode(disk) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func guessMime(from urlString: String) -> String? {
        let lower = urlString.lowercased()
        if lower.hasSuffix(".json") || lower.contains(".json?") { return "application/json" }
        if lower.hasSuffix(".vtt") || lower.contains(".vtt?") { return "text/vtt" }
        if lower.hasSuffix(".srt") || lower.contains(".srt?")
            || lower.hasSuffix(".srr") || lower.contains(".srr?") {
            return "application/srt"
        }
        return nil
    }

    private struct DiskTranscript: Codable {
        var sourceURL: String
        var mimeType: String?
        var plainText: String?
        var cues: [DiskCue]

        struct DiskCue: Codable {
            var startTimeSeconds: Double
            var endTimeSeconds: Double?
            var text: String
            var speaker: String?
        }

        init(from parsed: ParsedTranscript) {
            sourceURL = parsed.sourceURL
            mimeType = parsed.mimeType
            plainText = parsed.plainText
            cues = parsed.cues.map {
                DiskCue(
                    startTimeSeconds: $0.startTimeSeconds,
                    endTimeSeconds: $0.endTimeSeconds,
                    text: $0.text,
                    speaker: $0.speaker
                )
            }
        }

        var asParsed: ParsedTranscript {
            ParsedTranscript(
                cues: cues.map {
                    TranscriptCue(
                        startTimeSeconds: $0.startTimeSeconds,
                        endTimeSeconds: $0.endTimeSeconds,
                        text: $0.text,
                        speaker: $0.speaker
                    )
                },
                plainText: plainText,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
        }
    }
}

/// Best-effort VTT / SRT / JSON / plain-text extraction (no Whisper).
enum TranscriptParser {
    static func parse(body: String, mimeType: String?, sourceURL: String) -> ParsedTranscript {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let mime = TranscriptTypePreference.canonicalMime(from: mimeType)?.lowercased()
            ?? sniffMime(trimmed)

        var cues: [TranscriptCue] = []
        switch mime {
        case "application/json":
            cues = parseJSON(trimmed)
        case "text/vtt":
            cues = parseVTT(trimmed)
        case "application/srt":
            cues = parseSRT(trimmed)
        default:
            // Try timed formats by content before falling back to plain text.
            if trimmed.contains("-->") {
                if trimmed.lowercased().contains("webvtt") || trimmed.contains(".") {
                    cues = parseVTT(trimmed)
                }
                if cues.isEmpty {
                    cues = parseSRT(trimmed)
                }
            } else if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                cues = parseJSON(trimmed)
            }
        }

        let plain: String?
        if cues.isEmpty {
            plain = stripLightweightMarkup(trimmed)
        } else {
            plain = nil
        }

        return ParsedTranscript(
            cues: cues,
            plainText: plain,
            sourceURL: sourceURL,
            mimeType: mime ?? mimeType
        )
    }

    private static func sniffMime(_ body: String) -> String? {
        let lower = body.lowercased()
        if lower.hasPrefix("webvtt") { return "text/vtt" }
        if body.hasPrefix("{"), lower.contains("\"segments\"") { return "application/json" }
        if body.contains("-->"), body.contains(",") { return "application/srt" }
        if body.contains("-->") { return "text/vtt" }
        return nil
    }

    // MARK: - JSON (Podcast Index)

    private static func parseJSON(_ str: String) -> [TranscriptCue] {
        guard let data = str.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = root["segments"] as? [[String: Any]] else {
            return []
        }
        var cues: [TranscriptCue] = []
        for obj in segments {
            let start: Double
            if let n = obj["startTime"] as? Double {
                start = n
            } else if let n = obj["startTime"] as? Int {
                start = Double(n)
            } else if let s = obj["startTime"] as? String, let n = Double(s) {
                start = n
            } else {
                continue
            }
            let end: Double?
            if let n = obj["endTime"] as? Double {
                end = n
            } else if let n = obj["endTime"] as? Int {
                end = Double(n)
            } else if let s = obj["endTime"] as? String, let n = Double(s) {
                end = n
            } else {
                end = nil
            }
            let body = (obj["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !body.isEmpty else { continue }
            let speaker = (obj["speaker"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(
                TranscriptCue(
                    startTimeSeconds: start,
                    endTimeSeconds: end,
                    text: body,
                    speaker: (speaker?.isEmpty == false) ? speaker : nil
                )
            )
        }
        return cues
    }

    // MARK: - WebVTT

    private static func parseVTT(_ str: String) -> [TranscriptCue] {
        let normalized = str.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cues: [TranscriptCue] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1
            guard line.contains("-->") else { continue }
            guard let timings = parseVTTTimings(line) else { continue }
            var payloadParts: [String] = []
            while i < lines.count {
                let payloadLine = lines[i]
                i += 1
                if payloadLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                payloadParts.append(payloadLine.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            var payload = payloadParts.joined(separator: " ")
            var speaker: String?
            if let voice = extractVTTVoice(&payload) {
                speaker = voice
            }
            payload = stripLightweightMarkup(payload)
            guard !payload.isEmpty else { continue }
            cues.append(
                TranscriptCue(
                    startTimeSeconds: timings.start,
                    endTimeSeconds: timings.end,
                    text: payload,
                    speaker: speaker
                )
            )
        }
        return cues
    }

    private static func parseVTTTimings(_ line: String) -> (start: Double, end: Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        let startRaw = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let endToken = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        guard let start = parseVTTTimestamp(startRaw),
              let end = parseVTTTimestamp(endToken) else {
            return nil
        }
        return (start, end)
    }

    /// `HH:MM:SS.mmm` or `MM:SS.mmm`
    private static func parseVTTTimestamp(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:(\d{1,2}):)?(\d{2}):(\d{2})\.(\d{3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        else {
            return nil
        }
        func group(_ i: Int) -> Int {
            let r = match.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: trimmed) else { return 0 }
            return Int(trimmed[range]) ?? 0
        }
        let hours = group(1)
        let minutes = group(2)
        let seconds = group(3)
        let millis = group(4)
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(millis) / 1000.0
    }

    private static func extractVTTVoice(_ payload: inout String) -> String? {
        // <v Speaker>text
        let pattern = #"<v(?:\.[^\t\n\r &<>.]*)*[\t ]([^\n\r&>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: payload, range: NSRange(payload.startIndex..., in: payload)),
              match.numberOfRanges >= 2,
              let speakerRange = Range(match.range(at: 1), in: payload)
        else {
            return nil
        }
        let speaker = String(payload[speakerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let full = Range(match.range(at: 0), in: payload) {
            payload.removeSubrange(full)
        }
        return speaker.isEmpty ? nil : speaker
    }

    // MARK: - SRT

    private static func parseSRT(_ str: String) -> [TranscriptCue] {
        let normalized = str.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cues: [TranscriptCue] = []
        var i = 0
        while i < lines.count {
            var line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            i += 1
            if line.isEmpty { continue }
            // Optional numeric index line
            if line.allSatisfy(\.isNumber), i < lines.count, lines[i].contains("-->") {
                line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                i += 1
            }
            guard line.contains("-->") else { continue }
            let parts = line.components(separatedBy: "-->")
            guard parts.count >= 2,
                  let start = parseSRTTimestamp(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let end = parseSRTTimestamp(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                continue
            }
            var payloadParts: [String] = []
            while i < lines.count {
                let payloadLine = lines[i]
                i += 1
                if payloadLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                payloadParts.append(payloadLine.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            var payload = payloadParts.joined(separator: " ")
            var speaker: String?
            if let idx = payload.firstIndex(of: ":"),
               idx > payload.startIndex,
               idx < payload.index(payload.endIndex, offsetBy: -1),
               payload[payload.index(after: idx)].isWhitespace {
                let maybe = String(payload[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Heuristic: a short label like "Alice", "Dr. Smith", or "SPEAKER 1". Plain
                // cue text with a colon ("Here's the thing: …", "at 10:30") is not a speaker.
                if maybe.count <= 40, maybe.rangeOfCharacter(from: .letters) != nil,
                   Self.looksLikeSpeakerLabel(maybe) {
                    speaker = maybe
                    payload = String(payload[payload.index(after: idx)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            payload = stripLightweightMarkup(payload)
            guard !payload.isEmpty else { continue }
            cues.append(
                TranscriptCue(
                    startTimeSeconds: start,
                    endTimeSeconds: end,
                    text: payload,
                    speaker: speaker
                )
            )
        }
        return cues
    }

    /// At most three words, each starting with an uppercase letter or a digit.
    private static func looksLikeSpeakerLabel(_ label: String) -> Bool {
        let words = label.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard !words.isEmpty, words.count <= 3 else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            return first.isUppercase || first.isNumber
        }
    }

    /// `HH:MM:SS,mmm`
    private static func parseSRTTimestamp(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{2}):(\d{2}):(\d{2}),(\d{3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        else {
            // Also accept VTT-style dots in SRT files.
            return parseVTTTimestamp(trimmed.replacingOccurrences(of: ",", with: "."))
        }
        func group(_ i: Int) -> Int {
            let r = match.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: trimmed) else { return 0 }
            return Int(trimmed[range]) ?? 0
        }
        let hours = group(1)
        let minutes = group(2)
        let seconds = group(3)
        let millis = group(4)
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(millis) / 1000.0
    }

    // MARK: - Helpers

    private static func stripLightweightMarkup(_ s: String) -> String {
        var out = s
        // Remove simple HTML / VTT tags.
        if let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }
        return out
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriptCueIndexing {
    /// Index of the cue active at `positionSeconds`, or `nil` if before the first / empty.
    static func currentIndex(in cues: [TranscriptCue], at positionSeconds: Double) -> Int? {
        guard !cues.isEmpty else { return nil }
        var current: Int?
        for (i, cue) in cues.enumerated() {
            if cue.startTimeSeconds <= positionSeconds {
                current = i
            } else {
                break
            }
        }
        return current
    }
}
