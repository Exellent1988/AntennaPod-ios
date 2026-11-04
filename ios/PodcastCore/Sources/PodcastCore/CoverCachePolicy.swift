import Foundation

/// Android `prefImageCacheSize` ("Image cache size", MiB; Glide disk cache). Options and default
/// follow Android's preference list.
public enum CoverCachePolicy {
    public static let sizeOptionsMB: [Int] = [20, 50, 100, 250, 500]
    public static let defaultSizeMB = 100
    public static let defaultsKey = "settings.imageCacheSizeMB"

    public static func normalizedSizeMB(_ value: Int?) -> Int {
        guard let value, sizeOptionsMB.contains(value) else { return defaultSizeMB }
        return value
    }

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var bytes: Int64
        public var lastAccess: Date
        public init(name: String, bytes: Int64, lastAccess: Date) {
            self.name = name; self.bytes = bytes; self.lastAccess = lastAccess
        }
    }

    /// Least recently used first until the total fits `limitBytes`. Returns names to delete.
    public static func evictions(_ entries: [Entry], limitBytes: Int64) -> [String] {
        var total = entries.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > limitBytes else { return [] }
        var out: [String] = []
        for e in entries.sorted(by: { ($0.lastAccess, $0.name) < ($1.lastAccess, $1.name) }) {
            guard total > limitBytes else { break }
            out.append(e.name)
            total -= e.bytes
        }
        return out
    }
}
