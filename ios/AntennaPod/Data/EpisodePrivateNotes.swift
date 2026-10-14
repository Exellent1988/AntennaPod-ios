import Foundation

/// Local-only free-text private notes keyed by episode id (`episode-notes.json`).
/// Distinct from feed `FeedSettings.privateNote`, bookmark notes, chapters, and Share.
enum EpisodePrivateNotes {
    /// Max stored length (trim first; empty → nil). Same cap spirit as feed private notes.
    static let maxLength = 1000

    /// Trim, empty → nil, cap at `maxLength` (grapheme-aware via String count).
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxLength {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        let capped = String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }
}
