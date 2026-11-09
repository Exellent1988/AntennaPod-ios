import AVFoundation
import CryptoKit
import Foundation
import PodcastCore

/// Best-effort chapter markers embedded in a **local** media file, via AVFoundation only
/// (no third-party ID3/M4A/Vorbis parsers).
///
/// ## What works on iOS
/// - **QuickTime / MP4 chapter tracks** (text track associated with `chap`), exposed as
///   `AVTimedMetadataGroup` via `AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)`.
/// - Chapter titles from `.commonIdentifierTitle` (string-value fallback on group items).
///
/// ## What does **not** work reliably (documented honestly)
/// - **ID3v2 CHAP** frames (typical MP3 podcasts): AVFoundation does **not** surface them, so
///   `ID3ChapterParser` (PodcastCore, Android `ChapterReader` parity) reads them first.
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
        // MP3: ID3v2 CHAP (Android ChapterReader). AVFoundation does not expose these on iOS.
        let id3 = id3Chapters(fromFileURL: fileURL)
        if !id3.isEmpty { return id3 }
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

    /// ID3v2 CHAP chapters (title, WXXX link, APIC image). Embedded images are written to
    /// Caches/chapter-images and referenced by `file://` URL. `[]` when the file has no ID3 tag.
    static func id3Chapters(fromFileURL fileURL: URL) -> [PodcastChapter] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10),
              let length = ID3ChapterParser.tagLength(header: header),
              length <= 32 * 1024 * 1024 else { return [] }
        try? handle.seek(toOffset: 0)
        guard let tag = try? handle.read(upToCount: length) else { return [] }
        let parsed = ID3ChapterParser.chapters(in: tag)
        let key = SHA256.hash(data: Data(fileURL.lastPathComponent.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return parsed.enumerated().map { i, c in
            var image = c.imageURL
            if let data = c.imageData {
                image = writeChapterImage(data, mime: c.imageMimeType, name: "\(key)-\(i)")?.absoluteString
            }
            return PodcastChapter(title: c.title ?? String(localized: "Chapter"), startTimeSeconds: c.startSeconds,
                                  href: c.url, imageUrl: image)
        }
    }

    private static func writeChapterImage(_ data: Data, mime: String?, name: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("chapter-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = mime?.contains("png") == true ? "png" : "jpg"
        let url = dir.appendingPathComponent("\(name).\(ext)")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
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
