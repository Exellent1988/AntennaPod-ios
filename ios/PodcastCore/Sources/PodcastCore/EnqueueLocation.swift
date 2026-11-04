import Foundation

/// Android `prefEnqueueLocation` (UserPreferences.EnqueueLocation), default **Back**.
public enum EnqueueLocation: String, CaseIterable, Codable, Sendable {
    case back
    case front
    case afterCurrentlyPlaying
    case random

    public static let defaultLocation: EnqueueLocation = .back

    /// Unknown / missing raw values (older backups, future cases) fall back to Back.
    public init(storedValue: String?) {
        self = storedValue.flatMap(EnqueueLocation.init(rawValue:)) ?? .defaultLocation
    }
}

/// Android `ItemEnqueuePositionCalculator.calcPosition`.
public enum EnqueuePosition {
    /// 0-based insert index into `queueIds`.
    /// - Front / After currently playing skip past items that are still downloading, so episodes
    ///   enqueued one after another (e.g. tapping Download on several) keep their order.
    /// - After currently playing: right after the playing item when it is queued, otherwise the head.
    public static func index(
        location: EnqueueLocation,
        queueIds: [String],
        currentlyPlayingId: String?,
        isDownloading: (String) -> Bool = { _ in false },
        randomIndex: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) -> Int {
        switch location {
        case .back:
            return queueIds.count
        case .front:
            return firstNonDownloading(from: 0, queueIds, isDownloading)
        case .afterCurrentlyPlaying:
            let playing = currentlyPlayingId.flatMap { queueIds.firstIndex(of: $0) } ?? -1
            return firstNonDownloading(from: playing + 1, queueIds, isDownloading)
        case .random:
            return min(max(randomIndex(0...queueIds.count), 0), queueIds.count)
        }
    }

    private static func firstNonDownloading(from start: Int, _ ids: [String], _ isDownloading: (String) -> Bool) -> Int {
        var i = max(start, 0)
        while i < ids.count, isDownloading(ids[i]) { i += 1 }
        return min(i, ids.count)
    }
}
