import Foundation

/// Plain-text export of **local** episode bookmarks (already persisted in `bookmarks.json`).
/// The per-episode sheet exports positions; the catalog export adds episode/feed titles.
/// Never invents bookmarks; not gpodder.
struct BookmarkExportItem: Identifiable {
    let episodeTitle: String
    let feedTitle: String
    let bookmark: EpisodeBookmark
    let episodeId: String

    var id: String { "\(episodeId)-\(bookmark.id.uuidString)" }

    var displayEpisodeTitle: String {
        let value = episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? String(localized: "Episode") : value
    }

    var displayFeedTitle: String {
        let value = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? String(localized: "Podcast") : value
    }
}

enum BookmarksExport {
    /// Body only (no episode title). Empty when `bookmarks` is empty.
    static func plainText(from bookmarks: [EpisodeBookmark]) -> String {
        guard !bookmarks.isEmpty else { return "" }
        return bookmarks.map { line(for: $0) }.joined(separator: "\n")
    }

    /// Body for the full bookmarks catalog. The caller supplies catalog order; search filters do not apply.
    /// One line per bookmark: episode title, feed title, playback position, and optional note.
    static func plainText(items: [BookmarkExportItem]) -> String {
        guard !items.isEmpty else { return "" }
        return items.enumerated().map { index, item in
            var line = "\(index + 1). \(item.displayEpisodeTitle) — \(item.displayFeedTitle) — \(positionText(item.bookmark.positionSeconds))"
            let note = item.bookmark.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { line += " — \(note)" }
            return line
        }.joined(separator: "\n")
    }

    /// System share payload for the full catalog: localized header + blank line + body.
    static func shareText(items: [BookmarkExportItem]) -> String {
        let body = plainText(items: items)
        guard !body.isEmpty else { return "" }
        return "\(String(localized: "Bookmarks"))\n\n\(body)"
    }

    /// Playback timestamp in `m:ss` / `h:mm:ss` form.
    static func positionText(_ seconds: Double) -> String {
        formatPosition(seconds)
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
