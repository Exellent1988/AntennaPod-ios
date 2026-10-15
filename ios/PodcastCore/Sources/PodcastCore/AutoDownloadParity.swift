import Foundation

/// Android `AutomaticDownloadAlgorithm` / `NetworkUtils.isAutoDownloadAllowed` pieces that are
/// independent of the app types.
public enum AutoDownloadParity {
    /// Coarse device power state (iOS `UIDevice.BatteryState`).
    public enum PowerState: Equatable, Sendable { case charging, full, unplugged, unknown }

    /// Android `prefEnableAutoDownloadOnBattery` ("Download when not charging", default **on**).
    /// Off → automatic downloads only while charging. `unknown` (Simulator, monitoring unavailable)
    /// is allowed: iOS cannot tell, and nothing is invented.
    public static let defaultDownloadOnBattery = true

    public static func powerAllows(downloadOnBattery: Bool, power: PowerState) -> Bool {
        if downloadOnBattery { return true }
        switch power {
        case .charging, .full, .unknown: return true
        case .unplugged: return false
        }
    }

    /// Android candidates: the queue (in queue order) first, then new episodes not already in it.
    public static func candidateOrder<ID: Hashable>(queue: [ID], newcomers: [ID]) -> [ID] {
        var seen = Set<ID>()
        var out: [ID] = []
        for id in queue + newcomers where seen.insert(id).inserted { out.append(id) }
        return out
    }
}

/// Android Feed info → "Edit feed URL": the new address must be an http(s) URL that is not
/// the current one and not another subscription.
public enum FeedURLEdit {
    public enum Outcome: Equatable, Sendable {
        case ok(String)
        case invalid
        case unchanged
        case duplicate
    }

    public static func validate(_ raw: String, currentURLs: [String], otherFeedURLs: [String]) -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return .invalid }
        let key = FeedURLEquality.key(trimmed)
        guard !key.isEmpty else { return .invalid }
        if let current = currentURLs.first, FeedURLEquality.key(current) == key, current == trimmed { return .unchanged }
        if FeedURLEquality.keys(otherFeedURLs).contains(key) { return .duplicate }
        return .ok(trimmed)
    }
}
