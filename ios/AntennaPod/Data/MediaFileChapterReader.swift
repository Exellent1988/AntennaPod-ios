import AVFoundation
import Foundation

/// Best-effort chapter markers embedded in a **local** media file, via AVFoundation only
/// (no third-party ID3/M4A/Vorbis parsers).
///
/// ## What works on iOS
/// - **QuickTime / MP4 chapter tracks** (text track associated with `chap`), exposed as
///   `AVTimedMetadataGroup` via `AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)`.
/// - Chapter titles from `.commonIdentifierTitle` (string-value fallback on group items).
///
/// ## What does **not** work reliably (documented honestly)
/// - **ID3v2 CHAP** frames (typical MP3 podcasts): AVFoundation does **not** surface them as
///   chapter metadata groups on iOS. Android uses a dedicated `ChapterReader`; that path is not
///   implemented here and would need a custom ID3 parser (out of beta scope / no third-party libs).
/// - **Vorbis comment** chapters (Ogg/FLAC): same limitation without a custom parser.
/// - **Nero `chpl` atoms**: not walked manually; only appear if AVFoundation maps them into
///   chapter groups (best-effort, not guaranteed).
///
/// Only call for local `file://` URLs (downloaded episodes or local-folder feeds). Streaming
/// remote URLs are skipped — chapter I/O belongs on the on-disk asset.
enum MediaFileChapterReader {
    /// Reads chapter groups from a local file. Returns `[]` on missing file, unsupported tags, or errors.
    static func chapters(fromFileURL fileURL: URL) async -> [PodcastChapter] {
        guard fileURL.isFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let asset = AVURLAsset(url: fileURL)
        do {
            // Load chapter locales first (Apple guidance before chapterMetadataGroups).
            _ = try await asset.load(.availableChapterLocales)
            let preferred = Locale.preferredLanguages.isEmpty
                ? ["en"]
                : Locale.preferredLanguages
            let groups = try await asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: preferred
            )
            return mapGroups(groups)
        } catch {
            return []
        }
    }

    private static func mapGroups(_ groups: [AVTimedMetadataGroup]) -> [PodcastChapter] {
        var chapters: [PodcastChapter] = []
        for group in groups {
            let start = CMTimeGetSeconds(group.timeRange.start)
            guard start.isFinite, start >= 0 else { continue }
            let title = title(from: group.items) ?? String(localized: "Chapter")
            chapters.append(
                PodcastChapter(
                    title: title,
                    startTimeSeconds: start,
                    href: nil,
                    imageUrl: nil
                )
            )
        }
        return dedupeSorted(chapters)
    }

    private static func title(from items: [AVMetadataItem]) -> String? {
        let byId = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: .commonIdentifierTitle
        )
        if let s = byId.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        for item in items {
            if let s = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    private static func dedupeSorted(_ chapters: [PodcastChapter]) -> [PodcastChapter] {
        let sorted = chapters.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        var out: [PodcastChapter] = []
        for chapter in sorted {
            if let last = out.last, abs(last.startTimeSeconds - chapter.startTimeSeconds) < 0.05 {
                continue
            }
            out.append(chapter)
        }
        return out
    }
}
