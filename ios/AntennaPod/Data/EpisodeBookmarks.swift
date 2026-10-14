import Foundation

/// User-saved wall-clock playback position for an episode (local-only bookmarks).
/// Distinct from feed **chapters** and from **Share with position** (share text only).
struct EpisodeBookmark: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    /// Wall-clock seconds from episode start (not speed-adjusted).
    var positionSeconds: Double
    /// Optional short note (trimmed; may be empty).
    var note: String
    /// When the bookmark was created (epoch ms).
    var createdAtEpochMs: Int64

    init(
        id: UUID = UUID(),
        positionSeconds: Double,
        note: String = "",
        createdAtEpochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.positionSeconds = max(0, positionSeconds)
        self.note = note
        self.createdAtEpochMs = createdAtEpochMs
    }
}

extension EpisodeBookmark {
    /// Same keys as the synthesized decoder. `bookmarks.json` is replaced by a backup import;
    /// a position such as 1e20 crashed the Bookmarks sheet's `m:ss` / `h:mm:ss` formatter.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        positionSeconds = EpisodeDurationParsing.storedSeconds(
            try c.decode(Double.self, forKey: .positionSeconds)
        )
        note = try c.decode(String.self, forKey: .note)
        createdAtEpochMs = try c.decode(Int64.self, forKey: .createdAtEpochMs)
    }
}

/// Persistence helpers / caps for episode bookmarks (`bookmarks.json`).
enum EpisodeBookmarkStore {
    /// Soft cap per episode — Add is blocked with honesty when at cap.
    static let maxPerEpisode = 50
    /// Soft cap for optional note length (characters after trim).
    static let maxNoteLength = 120

    static func trimNote(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxNoteLength else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxNoteLength)
        return String(trimmed[..<idx])
    }

    /// Newest-first by `createdAtEpochMs` (stable id tiebreak).
    static func sortedNewestFirst(_ items: [EpisodeBookmark]) -> [EpisodeBookmark] {
        items.sorted { lhs, rhs in
            if lhs.createdAtEpochMs != rhs.createdAtEpochMs {
                return lhs.createdAtEpochMs > rhs.createdAtEpochMs
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
