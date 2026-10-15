import Foundation

/// Pure helpers for CarPlay / system Now Playing and artwork (no UIKit, unit-testable).
enum NowPlayingLogic {
    struct ChapterPosition: Equatable {
        let index: Int      // 0-based, as MPNowPlayingInfoPropertyChapterNumber expects
        let count: Int
        let title: String
    }

    /// Chapter containing `seconds` (last chapter whose start ≤ seconds). Chapters may be unsorted.
    static func chapter(at seconds: Double, starts: [(start: Double, title: String)]) -> ChapterPosition? {
        let sorted = starts.filter { $0.start.isFinite }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty, seconds.isFinite else { return nil }
        guard let idx = sorted.lastIndex(where: { $0.start <= seconds + 0.001 }) else { return nil }
        return ChapterPosition(index: idx, count: sorted.count, title: sorted[idx].title)
    }

    /// Artist line: chapter title when known (so CarPlay/lockscreen show it), else the podcast.
    static func artistLine(feedName: String, chapterTitle: String?) -> String {
        guard let c = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return feedName }
        return c
    }

    /// Supported rates for `changePlaybackRateCommand`: presets plus current, sorted, deduped (0.001 tolerance).
    static func supportedRates(presets: [Float], current: Float) -> [Float] {
        var out: [Float] = []
        for r in (presets + [current]).filter({ $0 > 0 }).sorted() where !out.contains(where: { abs($0 - r) < 0.001 }) {
            out.append(r)
        }
        return out
    }

    /// Snap a requested rate to the closest supported rate.
    static func nearestRate(_ requested: Float, supported: [Float]) -> Float? {
        supported.min { abs($0 - requested) < abs($1 - requested) }
    }

    /// Skip intervals for remote commands: positive whole seconds, defaults when unset/invalid.
    static func skipIntervals(rewind: Double, forward: Double) -> (back: Double, forward: Double) {
        func ok(_ v: Double, _ d: Double) -> Double { v.isFinite && v > 0 ? v.rounded() : d }
        return (ok(rewind, 10), ok(forward, 30))
    }

    // MARK: Artwork geometry

    struct Rect: Equatable { var x, y, width, height: Double }

    /// Aspect-fit `image` inside a `side`×`side` square, inset by `padding` on each edge, centered.
    static func aspectFitRect(imageWidth: Double, imageHeight: Double, side: Double, padding: Double = 0) -> Rect {
        let box = max(0, side - 2 * padding)
        guard imageWidth > 0, imageHeight > 0, box > 0 else { return Rect(x: 0, y: 0, width: side, height: side) }
        let scale = min(box / imageWidth, box / imageHeight)
        let w = imageWidth * scale, h = imageHeight * scale
        return Rect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
    }

    /// Padding for non-square art: none for (near-)square, else 4% of the side.
    static func padding(imageWidth: Double, imageHeight: Double, side: Double) -> Double {
        guard imageWidth > 0, imageHeight > 0 else { return 0 }
        let ratio = max(imageWidth, imageHeight) / min(imageWidth, imageHeight)
        return ratio < 1.02 ? 0 : (side * 0.04).rounded()
    }

    /// Stable disk-cache file name: FNV-1a 64-bit of the URL + pixel size (no CryptoKit needed).
    static func cacheFileName(url: String, pixels: Int) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in "\(pixels)|\(url)".utf8 { hash = (hash ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", hash) + ".png"
    }

    // MARK: Disk cache LRU

    struct CacheEntry: Equatable {
        let name: String
        let bytes: Int64
        let modified: Date
    }

    /// Default disk budget for CarPlay / Now Playing artwork.
    static let diskCacheLimitBytes: Int64 = 50 * 1024 * 1024

    /// Oldest-first (by mtime; name tiebreak) entries to delete so the total fits `limit`.
    static func evictions(_ entries: [CacheEntry], limit: Int64) -> [String] {
        var total = entries.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
        guard total > limit else { return [] }
        var out: [String] = []
        for e in entries.sorted(by: { $0.modified == $1.modified ? $0.name < $1.name : $0.modified < $1.modified }) {
            guard total > limit else { break }
            out.append(e.name)
            total -= max(0, e.bytes)
        }
        return out
    }

    // MARK: Android Auto skip parity

    enum TrackAction: Equatable { case skipEpisode, rewind, hardwareButton }

    /// Android PlaybackService: car-mode `onSkipToNext` → skip episode; `onSkipToPrevious` → rewind
    /// (no remap). Outside the car, iOS next/previous are headset keys → Android `handleKeycode`
    /// with `prefHardwareForwardButton` / `prefHardwarePreviousButton`.
    static func nextTrackAction(inCar: Bool) -> TrackAction { inCar ? .skipEpisode : .hardwareButton }
    static func previousTrackAction(inCar: Bool) -> TrackAction { inCar ? .rewind : .hardwareButton }

    /// Android `onNextChapter`: next chapter start, or `nil` → fall back to skipping the episode.
    static func nextChapterStart(starts: [Double], at seconds: Double) -> Double? {
        let sorted = starts.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        guard let idx = sorted.lastIndex(where: { $0 <= seconds + 0.001 }) else { return sorted[0] }
        return idx + 1 < sorted.count ? sorted[idx + 1] : nil
    }

    /// Minutes for the CarPlay sleep-timer toggle when off (Android default 15 min).
    static func sleepToggleMinutes(presets: [Int]) -> Int {
        presets.contains(15) ? 15 : (presets.first(where: { $0 > 0 }) ?? 15)
    }

    enum SleepToggleTarget: Equatable { case minutes(Int), episodes(Int) }

    /// Android `CUSTOM_ACTION_TOGGLE_SLEEP_TIMER` when off: `SleepTimerPreferences.timerMillisOrEpisodes()`,
    /// i.e. the last-used timer of the selected type (defaults 15 min / 1 episode).
    static func sleepToggleTarget(episodesKind: Bool, lastMinutes: Int, lastEpisodes: Int) -> SleepToggleTarget {
        episodesKind ? .episodes(lastEpisodes > 0 ? lastEpisodes : 1) : .minutes(lastMinutes > 0 ? lastMinutes : 15)
    }

    /// Android `CUSTOM_ACTION_CHANGE_PLAYBACK_SPEED`: next preset after the current one, wrapping; first preset
    /// when the current rate is not a preset; `nil` (no change) with fewer than two presets.
    static func nextSpeedPreset(presets: [Float], current: Float) -> Float? {
        guard presets.count > 1 else { return nil }
        guard let idx = presets.firstIndex(where: { abs($0 - current) < 0.001 }) else { return presets[0] }
        return idx + 1 < presets.count ? presets[idx + 1] : presets[0]
    }

    enum NowPlayingButton: Equatable { case rate, sleepTimer, nextChapter, skipEpisode }

    /// Android Auto custom-action order (rewind/FF are system skip buttons on CarPlay):
    /// speed, sleep timer, next chapter (only with chapters), skip episode. CarPlay allows ≤ 5.
    static func nowPlayingButtons(hasChapters: Bool) -> [NowPlayingButton] {
        var out: [NowPlayingButton] = [.rate, .sleepTimer]
        if hasChapters { out.append(.nextChapter) }
        out.append(.skipEpisode)
        return out
    }
}
