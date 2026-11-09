import Foundation

/// Resolves which chapter list to show when both feed and media-file sources exist.
///
/// ## Preference (beta, documented)
/// 1. **Feed chapters win wholesale** when non-empty — Podlove Simple Chapters (inline) or
///    Podcast Index JSON (fetched). Keeps feed titles, `href`, and images intact.
/// 2. **Else** use **media-file chapters** from `MediaFileChapterReader` (QuickTime/MP4 chapter
///    tracks via AVFoundation on a local file).
///
/// This is **not** Android `ChapterMerger.merge` (same-length field fill / longer-list wins).
/// No union-by-start-time: mixing PSC titles with media markers for the same offsets is easy to
/// get wrong and harder to explain in beta. Prefer one coherent list.
enum ChapterMerger {
    /// Prefer `feed` when it has markers; otherwise return `media`.
    static func preferFeed(_ feed: [PodcastChapter], elseMedia media: [PodcastChapter]) -> [PodcastChapter] {
        if !feed.isEmpty { return feed }
        return media
    }
}
