import Foundation
import SwiftUI

/// Appearance preference persisted for `preferredColorScheme`.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` follows the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Max size of Documents/downloads (P0 Speicherverwaltung).
/// AntennaPod Android uses an episode *count* cache; iOS beta uses a byte budget instead.
enum DownloadStorageLimit: Equatable, Hashable, Identifiable {
    case unlimited
    case gigabytes(Int)
    case customMegabytes(Int)

    var id: String {
        switch self {
        case .unlimited: return "unlimited"
        case .gigabytes(let gb): return "gb-\(gb)"
        case .customMegabytes(let mb): return "custom-\(mb)"
        }
    }

    /// `nil` means no eviction by size.
    var byteLimit: Int64? {
        switch self {
        case .unlimited:
            return nil
        case .gigabytes(let gb):
            return Int64(gb) * 1_024 * 1_024 * 1_024
        case .customMegabytes(let mb):
            return Int64(max(1, mb)) * 1_024 * 1_024
        }
    }

    var label: String {
        switch self {
        case .unlimited:
            return "Unlimited"
        case .gigabytes(let gb):
            return "\(gb) GB"
        case .customMegabytes(let mb):
            return "\(mb) MB"
        }
    }

    /// Presets shown in the Settings picker (custom is selected separately when MB ≠ presets).
    static let pickerPresets: [DownloadStorageLimit] = [
        .unlimited,
        .gigabytes(1),
        .gigabytes(5),
        .gigabytes(10),
        .customMegabytes(500)
    ]
}

/// How often subscribed feeds are auto-refreshed (global; all feeds).
enum FeedRefreshInterval: String, CaseIterable, Identifiable {
    case manual
    case oneHour
    case fourHours
    case twelveHours
    case twentyFourHours

    var id: String { rawValue }

    /// `nil` means never auto-refresh (manual / pull-to-refresh only).
    var timeInterval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .oneHour: return 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .manual: return "Manual only"
        case .oneHour: return "Every 1 hour"
        case .fourHours: return "Every 4 hours"
        case .twelveHours: return "Every 12 hours"
        case .twentyFourHours: return "Every 24 hours"
        }
    }
}

/// User preferences for P0 Settings (theme, default playback speed, download storage limit, refresh).
@MainActor
final class AppSettings: ObservableObject {
    static let speedPresets: [Float] = [0.8, 1.0, 1.2, 1.5, 2.0]
    static let customStorageMBRange = 50...100_000

    private enum Keys {
        static let theme = "settings.theme"
        static let defaultPlaybackSpeed = "settings.defaultPlaybackSpeed"
        static let storageLimitKind = "settings.storageLimit.kind"
        static let storageLimitValue = "settings.storageLimit.value"
        static let refreshInterval = "settings.refreshInterval"
        static let lastFeedRefreshAt = "settings.lastFeedRefreshAt"
    }

    private enum Kind: String {
        case unlimited
        case gigabytes
        case customMegabytes
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    @Published var defaultPlaybackSpeed: Float {
        didSet {
            UserDefaults.standard.set(defaultPlaybackSpeed, forKey: Keys.defaultPlaybackSpeed)
        }
    }

    /// Max download folder size. Changing it persists immediately; callers should run eviction.
    @Published var downloadStorageLimit: DownloadStorageLimit {
        didSet {
            persistStorageLimit()
        }
    }

    /// Global auto-refresh cadence for all subscribed feeds (Keep updated).
    @Published var refreshInterval: FeedRefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
    }

    /// Wall-clock of the last completed `refreshAllFeeds()` (manual or automatic).
    @Published var lastFeedRefreshAt: Date? {
        didSet {
            if let lastFeedRefreshAt {
                UserDefaults.standard.set(lastFeedRefreshAt.timeIntervalSince1970, forKey: Keys.lastFeedRefreshAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastFeedRefreshAt)
            }
        }
    }

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.system.rawValue
        theme = AppTheme(rawValue: themeRaw) ?? .system
        if UserDefaults.standard.object(forKey: Keys.defaultPlaybackSpeed) != nil {
            let stored = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
            defaultPlaybackSpeed = Self.speedPresets.contains(stored) ? stored : 1.0
        } else {
            defaultPlaybackSpeed = 1.0
        }
        downloadStorageLimit = Self.loadStorageLimit()
        let intervalRaw = UserDefaults.standard.string(forKey: Keys.refreshInterval)
            ?? FeedRefreshInterval.manual.rawValue
        refreshInterval = FeedRefreshInterval(rawValue: intervalRaw) ?? .manual
        if UserDefaults.standard.object(forKey: Keys.lastFeedRefreshAt) != nil {
            let epoch = UserDefaults.standard.double(forKey: Keys.lastFeedRefreshAt)
            lastFeedRefreshAt = Date(timeIntervalSince1970: epoch)
        } else {
            lastFeedRefreshAt = nil
        }
    }

    /// `true` when interval is not manual and enough time has passed since the last refresh
    /// (or never refreshed yet).
    var isFeedRefreshDue: Bool {
        guard let interval = refreshInterval.timeInterval else { return false }
        guard let last = lastFeedRefreshAt else { return true }
        return Date().timeIntervalSince(last) >= interval
    }

    /// Record a completed full refresh so the next due-check starts from now.
    func markFeedRefreshCompleted(at date: Date = Date()) {
        lastFeedRefreshAt = date
    }

    /// Apply a custom MB budget from the Settings stepper / text field.
    func setCustomStorageLimitMegabytes(_ megabytes: Int) {
        let clamped = min(max(megabytes, Self.customStorageMBRange.lowerBound), Self.customStorageMBRange.upperBound)
        downloadStorageLimit = .customMegabytes(clamped)
    }

    private func persistStorageLimit() {
        switch downloadStorageLimit {
        case .unlimited:
            UserDefaults.standard.set(Kind.unlimited.rawValue, forKey: Keys.storageLimitKind)
            UserDefaults.standard.removeObject(forKey: Keys.storageLimitValue)
        case .gigabytes(let gb):
            UserDefaults.standard.set(Kind.gigabytes.rawValue, forKey: Keys.storageLimitKind)
            UserDefaults.standard.set(gb, forKey: Keys.storageLimitValue)
        case .customMegabytes(let mb):
            UserDefaults.standard.set(Kind.customMegabytes.rawValue, forKey: Keys.storageLimitKind)
            UserDefaults.standard.set(mb, forKey: Keys.storageLimitValue)
        }
    }

    private static func loadStorageLimit() -> DownloadStorageLimit {
        let kindRaw = UserDefaults.standard.string(forKey: Keys.storageLimitKind) ?? Kind.unlimited.rawValue
        let value = UserDefaults.standard.integer(forKey: Keys.storageLimitValue)
        switch Kind(rawValue: kindRaw) {
        case .unlimited, .none:
            return .unlimited
        case .gigabytes:
            let gb = [1, 5, 10].contains(value) ? value : 5
            return .gigabytes(gb)
        case .customMegabytes:
            let mb = value > 0 ? value : 500
            return .customMegabytes(mb)
        }
    }
}
