import Foundation

/// Android `UserPreferences.prefMobileUpdateTypes`: the multi-select "Mobile updates" list of what
/// may use mobile data (cellular). Raw values are Android's entry values.
public enum MobileUpdateType: String, CaseIterable, Codable, Sendable {
    case feedRefresh = "feed_refresh"
    case episodeDownload = "episode_download"
    case autoDownload = "auto_download"
    case streaming
    case images
}

public enum MobileUpdateTypes {
    /// UserDefaults key (prefix `settings.` → watched by the settings leak check).
    public static let defaultsKey = "settings.mobileUpdateTypes"
    /// Android default for a fresh install: only images.
    public static let androidDefault: Set<MobileUpdateType> = [.images]

    /// iOS builds before this model had three Wi‑Fi-only toggles and no gate for feed refresh or
    /// images (both always used mobile data). Keep exactly that behaviour on update and for new
    /// installs (iOS defaults: auto-download Wi‑Fi only on, manual download / stream off).
    public static func migrated(autoDownloadWifiOnly: Bool?, manualDownloadWifiOnly: Bool?,
                                streamWifiOnly: Bool?) -> Set<MobileUpdateType> {
        var set: Set<MobileUpdateType> = [.feedRefresh, .images]
        if !(autoDownloadWifiOnly ?? true) { set.insert(.autoDownload) }
        if !(manualDownloadWifiOnly ?? false) { set.insert(.episodeDownload) }
        if !(streamWifiOnly ?? false) { set.insert(.streaming) }
        return set
    }

    /// Sorted Android raw values (stable for UserDefaults / backup).
    public static func encode(_ set: Set<MobileUpdateType>) -> [String] {
        MobileUpdateType.allCases.filter(set.contains).map(\.rawValue)
    }

    /// Unknown values are ignored (a newer Android/iOS build may add types).
    public static func decode(_ raw: [String]) -> Set<MobileUpdateType> {
        Set(raw.compactMap(MobileUpdateType.init(rawValue:)))
    }

    /// The transfer may run on the current path: Wi‑Fi / Ethernet always; cellular (or other
    /// metered path) only when the type is allowed; offline never.
    public static func allows(_ type: MobileUpdateType, in set: Set<MobileUpdateType>,
                              isOffline: Bool, isUnmetered: Bool) -> Bool {
        if isOffline { return false }
        if isUnmetered { return true }
        return set.contains(type)
    }
}

/// Android `FeedUpdateManager.runOnceOrAsk`: a feed refresh on mobile data that is not allowed is
/// skipped. A user-started refresh asks (Refresh anyway / Always allow / Cancel); an automatic
/// refresh is skipped silently.
public enum FeedRefreshNetworkDecision: Equatable, Sendable {
    case run
    case askUser
    case skip

    public static func decide(userInitiated: Bool, allowOnceOnMobile: Bool, allowed: Bool) -> Self {
        if allowed || allowOnceOnMobile { return .run }
        return userInitiated ? .askUser : .skip
    }
}
