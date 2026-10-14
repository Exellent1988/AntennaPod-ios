import Foundation

/// Plain-text export of the full persisted download-error ring buffer (`DownloadService.recentErrors`).
/// The input order is preserved: the store keeps newest failures first, so the export is newest first.
/// It does not follow the Download errors search filter and includes only fields present on
/// `DownloadErrorEntry` (episode title, feed title, and message).
/// Local plain text only — not OPML, not gpodder, not a deep link.
enum DownloadErrorsExport {
    /// Body only (no “Download errors” header). Empty when `entries` is empty.
    static func plainText(from entries: [DownloadErrorEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.enumerated().map { index, entry in
            line(index: index + 1, entry: entry)
        }.joined(separator: "\n")
    }

    /// System share payload: localized “Download errors” header + blank line + body.
    /// Empty when `entries` is empty.
    static func shareText(from entries: [DownloadErrorEntry]) -> String {
        let body = plainText(from: entries)
        guard !body.isEmpty else { return "" }
        let header = String(localized: "Download errors")
        return "\(header)\n\n\(body)"
    }

    private static func line(index: Int, entry: DownloadErrorEntry) -> String {
        let fields = [entry.episodeTitle, entry.feedTitle, entry.message]
            .map(singleLine)
            .filter { !$0.isEmpty }
        return "\(index). \(fields.joined(separator: " — "))"
    }

    /// Keep the promised one-line-per-entry shape even when a server error contains newlines.
    private static func singleLine(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
