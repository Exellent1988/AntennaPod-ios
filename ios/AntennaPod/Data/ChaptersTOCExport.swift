import Foundation

/// Plain-text table of contents from **already-known** chapters only.
/// One line per chapter: `mm:ss Title` or `h:mm:ss Title` (start time); optional href on the same line.
/// Empty/whitespace titles → localized **Chapter**. Callers must pass the **full** chapter array
/// (ignore any UI search filter) — same honesty as transcript Copy/Share.
enum ChaptersTOCExport {
    /// TOC body only (no episode title). Empty when `chapters` is empty.
    static func plainText(from chapters: [PodcastChapter]) -> String {
        guard !chapters.isEmpty else { return "" }
        return chapters.map { plainLine(for: $0) }.joined(separator: "\n")
    }

    /// System share payload: optional episode title + blank line + TOC body (same body as `plainText`).
    static func shareText(from chapters: [PodcastChapter], episodeTitle: String?) -> String {
        let body = plainText(from: chapters)
        guard !body.isEmpty else { return "" }
        let title = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty { return body }
        return "\(title)\n\n\(body)"
    }

    /// One TOC line for a single chapter — same format as each row of `plainText`.
    static func plainLine(for chapter: PodcastChapter) -> String {
        let time = formatStart(chapter.startTimeSeconds)
        var title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = String(localized: "Chapter")
        }
        var result = "\(time) \(title)"
        if let href = chapter.href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty {
            result += " \(href)"
        }
        return result
    }

    /// One-line pasteboard text for the chapter active at `positionSeconds`.
    /// Uses `ChapterIndexing.currentIndex` (same as title highlight / artwork).
    /// Reads from the **full** array — ignores any UI search filter. Nil when no current chapter.
    static func currentChapterPlainText(
        from chapters: [PodcastChapter],
        at positionSeconds: Double
    ) -> String? {
        guard let index = ChapterIndexing.currentIndex(in: chapters, at: positionSeconds),
              chapters.indices.contains(index) else { return nil }
        return plainLine(for: chapters[index])
    }

    /// System share payload: optional episode title + blank line + current chapter line
    /// (same body as `currentChapterPlainText`). Empty when no current chapter.
    static func currentChapterShareText(
        from chapters: [PodcastChapter],
        at positionSeconds: Double,
        episodeTitle: String?
    ) -> String {
        guard let body = currentChapterPlainText(from: chapters, at: positionSeconds),
              !body.isEmpty else { return "" }
        let title = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty { return body }
        return "\(title)\n\n\(body)"
    }

    /// Start time `m:ss` / `h:mm:ss` — same as chapter list / scrubber formatters.
    private static func formatStart(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
