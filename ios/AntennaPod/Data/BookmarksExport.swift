import Foundation

/// Plain-text export of **local** episode bookmarks (already persisted in `bookmarks.json`).
/// One line per bookmark matching list order (newest-first): `m:ss` / `h:mm:ss`, plus note when non-empty.
/// Callers must pass the same ordered array the sheet shows — never invent bookmarks; not gpodder.
enum BookmarksExport {
    /// Body only (no episode title). Empty when `bookmarks` is empty.
    static func plainText(from bookmarks: [EpisodeBookmark]) -> String {
        guard !bookmarks.isEmpty else { return "" }
        return bookmarks.map { line(for: $0) }.joined(separator: "\n")
    }

    /// System share / header payload: optional episode title + blank line + body (same body as `plainText`).
    static func shareText(from bookmarks: [EpisodeBookmark], episodeTitle: String?) -> String {
        let body = plainText(from: bookmarks)
        guard !body.isEmpty else { return "" }
        let title = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty { return body }
        return "\(title)\n\n\(body)"
    }

    private static func line(for bookmark: EpisodeBookmark) -> String {
        let time = formatPosition(bookmark.positionSeconds)
        let note = bookmark.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty { return time }
        return "\(time) \(note)"
    }

    /// Wall-clock `m:ss` / `h:mm:ss` — same as bookmark list / scrubber formatters.
    private static func formatPosition(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
