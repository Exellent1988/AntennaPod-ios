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


/// How many newest unplayed episodes per feed auto-download may enqueue after refresh.
enum AutoDownloadEpisodesPerFeed: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .one: return "1 episode"
        case .two: return "2 episodes"
        case .three: return "3 episodes"
        case .five: return "5 episodes"
        }
    }
}


/// Preferred media source when starting playback (P0 Prefer stream vs download).
enum PlaybackSourcePreference: String, CaseIterable, Identifiable {
    /// Use local file when present; otherwise stream.
    case preferDownload
    /// Always use the network media URL, even if a download exists.
    case preferStream
    /// Default: local file if present, else stream (same resolution as prefer download).
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preferDownload: return "Prefer download"
        case .preferStream: return "Prefer stream"
        case .automatic: return "Automatic"
        }
    }

    var helpText: String {
        switch self {
        case .preferDownload:
            return "Play the offline file when available; otherwise stream from the network."
        case .preferStream:
            return "Always stream from the network URL, even if the episode is downloaded."
        case .automatic:
            return "Use the local file when it exists; otherwise stream. Default."
        }
    }
}


/// Charts country for iTunes top podcasts. Empty / `auto` → device locale (fallback `de`).
enum ChartsCountryPreference: Equatable, Hashable, Identifiable {
    case automatic
    case code(String)

    var id: String {
        switch self {
        case .automatic: return "auto"
        case .code(let c): return c.lowercased()
        }
    }

    var storageValue: String {
        switch self {
        case .automatic: return "auto"
        case .code(let c): return c.lowercased()
        }
    }

    static func fromStorage(_ raw: String?) -> ChartsCountryPreference {
        let v = (raw ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty || v == "auto" { return .automatic }
        let code = ItunesTopListService.normalizedCountryCode(v)
        return code.isEmpty ? .automatic : .code(code)
    }

    /// Curated picker list (ISO alpha-2); includes common AntennaPod locales.
    static let pickerCodes: [String] = [
        "de", "at", "ch", "us", "gb", "ie", "fr", "nl", "be", "es", "it",
        "pt", "pl", "se", "no", "dk", "fi", "cz", "au", "ca", "jp", "br", "mx", "in"
    ]
}

/// User preferences for P0 Settings (theme, default playback speed, download storage limit, refresh, new-episode action, auto-download, network/Wi‑Fi policy, playback source, auto-delete, skip intervals, skip intro/outro, volume adaptation, skip silence preference, new-episode / download-error / sync-error notifications, App Store rating prompt, play video as audio only).
@MainActor
final class AppSettings: ObservableObject {
    static let speedPresets: [Float] = [0.8, 1.0, 1.2, 1.5, 2.0]
    /// Common AntennaPod-style skip presets (Settings pickers + player buttons).
    static let skipIntervalPresets: [Int] = [5, 10, 15, 20, 30, 60]
    /// Skip intro / outro presets (0 = off). Matches common AntennaPod values.
    static let skipIntroOutroPresets: [Int] = [0, 5, 10, 15, 30, 60]
    /// Android `prefRewindSecs` default.
    static let defaultRewindSeconds: Int = 10
    /// Android `prefFastForwardSecs` default.
    static let defaultFastForwardSeconds: Int = 30
    /// Global skip intro / outro default (off).
    static let defaultSkipIntroOutroSeconds: Int = 0
    static let customStorageMBRange = 50...100_000

    /// SF Symbol for skip buttons (`gobackward.10`, `goforward.30`, …). Falls back to unnumbered glyph when no preset icon exists (e.g. 20s).
    static func skipSystemImage(forward: Bool, seconds: Int) -> String {
        let base = forward ? "goforward" : "gobackward"
        switch seconds {
        case 5, 10, 15, 30, 45, 60, 75, 90:
            return "\(base).\(seconds)"
        default:
            return base
        }
    }

    private enum Keys {
        static let theme = "settings.theme"
        static let defaultPlaybackSpeed = "settings.defaultPlaybackSpeed"
        static let storageLimitKind = "settings.storageLimit.kind"
        static let storageLimitValue = "settings.storageLimit.value"
        static let refreshInterval = "settings.refreshInterval"
        static let lastFeedRefreshAt = "settings.lastFeedRefreshAt"
        static let newEpisodeAction = "settings.newEpisodeAction"
        static let autoDownloadEnabled = "settings.autoDownload.enabled"
        static let autoDownloadEpisodesPerFeed = "settings.autoDownload.episodesPerFeed"
        static let autoDownloadWifiOnly = "settings.autoDownload.wifiOnly"
        static let manualDownloadWifiOnly = "settings.manualDownload.wifiOnly"
        static let streamWifiOnly = "settings.stream.wifiOnly"
        static let playbackSourcePreference = "settings.playbackSourcePreference"
        static let autoDeleteAfterPlaying = "settings.autoDelete.afterPlaying"
        static let rewindSeconds = "settings.rewindSeconds"
        static let fastForwardSeconds = "settings.fastForwardSeconds"
        static let skipIntroSeconds = "settings.skipIntroSeconds"
        static let skipOutroSeconds = "settings.skipOutroSeconds"
        static let notifyOnNewEpisodes = "settings.notifyOnNewEpisodes"
        static let notifyOnDownloadErrors = "settings.notifyOnDownloadErrors"
        static let notifyOnSyncErrors = "settings.notifyOnSyncErrors"
        static let chartsCountryCode = "settings.chartsCountryCode"
        static let askForAppStoreRating = "settings.askForAppStoreRating"
        static let playVideoAsAudioOnly = "settings.playVideoAsAudioOnly"
        static let volumeAdaptationEnabled = "settings.volumeAdaptationEnabled"
        static let skipSilenceEnabled = "settings.skipSilenceEnabled"
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

    /// Global action for newly discovered episodes after refresh (Inbox only / Queue / Queue+download).
    @Published var newEpisodeAction: NewEpisodeAction {
        didSet {
            UserDefaults.standard.set(newEpisodeAction.rawValue, forKey: Keys.newEpisodeAction)
        }
    }

    /// Global auto-download after feed refresh (newest unplayed, not yet downloaded).
    @Published var autoDownloadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadEnabled, forKey: Keys.autoDownloadEnabled)
        }
    }

    /// Cap per feed to avoid download storms (1 / 2 / 3 / 5).
    @Published var autoDownloadEpisodesPerFeed: AutoDownloadEpisodesPerFeed {
        didSet {
            UserDefaults.standard.set(autoDownloadEpisodesPerFeed.rawValue, forKey: Keys.autoDownloadEpisodesPerFeed)
        }
    }

    /// When true, auto-download enqueues only on Wi‑Fi / Ethernet (`NWPathMonitor`).
    @Published var autoDownloadWifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadWifiOnly, forKey: Keys.autoDownloadWifiOnly)
        }
    }

    /// When true, manual downloads are refused on cellular (error recorded; default off).
    @Published var manualDownloadWifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(manualDownloadWifiOnly, forKey: Keys.manualDownloadWifiOnly)
        }
    }

    /// When true, `PlaybackService` refuses stream URLs on cellular; local files still play (default off).
    @Published var streamWifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(streamWifiOnly, forKey: Keys.streamWifiOnly)
        }
    }

    /// Prefer local download, always stream, or automatic (local if present).
    @Published var playbackSourcePreference: PlaybackSourcePreference {
        didSet {
            UserDefaults.standard.set(playbackSourcePreference.rawValue, forKey: Keys.playbackSourcePreference)
        }
    }

    /// When true, delete the local download after an episode is marked played (file only; DB row kept).
    @Published var autoDeleteAfterPlaying: Bool {
        didSet {
            UserDefaults.standard.set(autoDeleteAfterPlaying, forKey: Keys.autoDeleteAfterPlaying)
        }
    }

    /// Seconds to jump backward on rewind / skip-back (Android `prefRewindSecs`, default 10).
    @Published var rewindSeconds: Int {
        didSet {
            UserDefaults.standard.set(rewindSeconds, forKey: Keys.rewindSeconds)
        }
    }

    /// Seconds to jump forward on fast-forward / skip-forward (Android `prefFastForwardSecs`, default 30).
    @Published var fastForwardSeconds: Int {
        didSet {
            UserDefaults.standard.set(fastForwardSeconds, forKey: Keys.fastForwardSeconds)
        }
    }

    /// Seconds to skip at the start of an episode on a fresh play (0 = off). Global only in this beta.
    @Published var skipIntroSeconds: Int {
        didSet {
            UserDefaults.standard.set(skipIntroSeconds, forKey: Keys.skipIntroSeconds)
        }
    }

    /// When remaining playback ≤ this many seconds, treat the episode as finished (0 = off). Global only.
    @Published var skipOutroSeconds: Int {
        didSet {
            UserDefaults.standard.set(skipOutroSeconds, forKey: Keys.skipOutroSeconds)
        }
    }

    /// Notify when feed refresh discovers new episodes (local UserNotifications; no push).
    /// Defaults on; actual delivery still requires system permission (Settings stays honest if denied).
    @Published var notifyOnNewEpisodes: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnNewEpisodes, forKey: Keys.notifyOnNewEpisodes)
        }
    }

    /// Notify when an episode download fails (local UserNotifications; no push).
    /// Defaults on; shares the same system permission as new-episode alerts.
    @Published var notifyOnDownloadErrors: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnDownloadErrors, forKey: Keys.notifyOnDownloadErrors)
        }
    }

    /// Notify when gpodder / Nextcloud login or sync fails (local UserNotifications; no push).
    /// Defaults on; shares the same system permission as new-episode / download-error alerts.
    @Published var notifyOnSyncErrors: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnSyncErrors, forKey: Keys.notifyOnSyncErrors)
        }
    }

    /// iTunes top-lists country: `"auto"` (device locale → else `de`) or ISO alpha-2 (`de`, `us`, …).
    @Published var chartsCountryCode: String {
        didSet {
            UserDefaults.standard.set(chartsCountryCode, forKey: Keys.chartsCountryCode)
        }
    }


    /// When true, after ~10 successful mark-played events ask iOS once for an App Store rating sheet.
    /// Defaults on; iOS may still suppress the dialog (system limits). Reset via Settings for testing.
    @Published var askForAppStoreRating: Bool {
        didSet {
            UserDefaults.standard.set(askForAppStoreRating, forKey: Keys.askForAppStoreRating)
        }
    }

    /// When true, video episodes hide the full-player video surface and show artwork (audio-style).
    /// Default off; Lockscreen / Now Playing stays audio either way. Media item is unchanged (lite).
    @Published var playVideoAsAudioOnly: Bool {
        didSet {
            UserDefaults.standard.set(playVideoAsAudioOnly, forKey: Keys.playVideoAsAudioOnly)
        }
    }

    /// When true, `PlaybackService` sets `AVAudioSession` mode to `.spokenAudio` (speech-oriented session mode).
    /// Default off. This is an **iOS session mode**, not Android's LoudnessEnhancer gain curve.
    @Published var volumeAdaptationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(volumeAdaptationEnabled, forKey: Keys.volumeAdaptationEnabled)
        }
    }

    /// Preference for skip-silence (AntennaPod Android / ExoPlayer). Default off.
    /// **Not applied** on stock `AVPlayer` — needs a custom `AVAudioEngine` graph (would break shared video / Now Playing). Toggle is honest UI + future hook only.
    @Published var skipSilenceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(skipSilenceEnabled, forKey: Keys.skipSilenceEnabled)
        }
    }

    /// Resolved ISO country used for chart requests.
    var resolvedChartsCountryCode: String {
        let pref = ChartsCountryPreference.fromStorage(chartsCountryCode)
        switch pref {
        case .automatic:
            return ItunesTopListService.defaultCountryCode()
        case .code(let c):
            return c
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
        let actionRaw = UserDefaults.standard.string(forKey: Keys.newEpisodeAction)
            ?? NewEpisodeAction.inboxOnly.rawValue
        newEpisodeAction = NewEpisodeAction(rawValue: actionRaw) ?? .inboxOnly
        if UserDefaults.standard.object(forKey: Keys.autoDownloadEnabled) != nil {
            autoDownloadEnabled = UserDefaults.standard.bool(forKey: Keys.autoDownloadEnabled)
        } else {
            autoDownloadEnabled = false
        }
        let perFeedRaw = UserDefaults.standard.object(forKey: Keys.autoDownloadEpisodesPerFeed) as? Int
            ?? AutoDownloadEpisodesPerFeed.two.rawValue
        autoDownloadEpisodesPerFeed = AutoDownloadEpisodesPerFeed(rawValue: perFeedRaw) ?? .two
        if UserDefaults.standard.object(forKey: Keys.autoDownloadWifiOnly) != nil {
            autoDownloadWifiOnly = UserDefaults.standard.bool(forKey: Keys.autoDownloadWifiOnly)
        } else {
            autoDownloadWifiOnly = true
        }
        if UserDefaults.standard.object(forKey: Keys.manualDownloadWifiOnly) != nil {
            manualDownloadWifiOnly = UserDefaults.standard.bool(forKey: Keys.manualDownloadWifiOnly)
        } else {
            manualDownloadWifiOnly = false
        }
        if UserDefaults.standard.object(forKey: Keys.streamWifiOnly) != nil {
            streamWifiOnly = UserDefaults.standard.bool(forKey: Keys.streamWifiOnly)
        } else {
            streamWifiOnly = false
        }
        let sourceRaw = UserDefaults.standard.string(forKey: Keys.playbackSourcePreference)
            ?? PlaybackSourcePreference.automatic.rawValue
        playbackSourcePreference = PlaybackSourcePreference(rawValue: sourceRaw) ?? .automatic
        if UserDefaults.standard.object(forKey: Keys.autoDeleteAfterPlaying) != nil {
            autoDeleteAfterPlaying = UserDefaults.standard.bool(forKey: Keys.autoDeleteAfterPlaying)
        } else {
            autoDeleteAfterPlaying = false
        }
        rewindSeconds = Self.loadSkipSeconds(
            key: Keys.rewindSeconds,
            defaultValue: Self.defaultRewindSeconds
        )
        fastForwardSeconds = Self.loadSkipSeconds(
            key: Keys.fastForwardSeconds,
            defaultValue: Self.defaultFastForwardSeconds
        )
        skipIntroSeconds = Self.loadSkipIntroOutroSeconds(key: Keys.skipIntroSeconds)
        skipOutroSeconds = Self.loadSkipIntroOutroSeconds(key: Keys.skipOutroSeconds)
        if UserDefaults.standard.object(forKey: Keys.notifyOnNewEpisodes) != nil {
            notifyOnNewEpisodes = UserDefaults.standard.bool(forKey: Keys.notifyOnNewEpisodes)
        } else {
            // Default on; permission gate is separate (honest if denied).
            notifyOnNewEpisodes = true
        }
        if UserDefaults.standard.object(forKey: Keys.notifyOnDownloadErrors) != nil {
            notifyOnDownloadErrors = UserDefaults.standard.bool(forKey: Keys.notifyOnDownloadErrors)
        } else {
            // Default on; same permission gate as new-episode alerts.
            notifyOnDownloadErrors = true
        }
        if UserDefaults.standard.object(forKey: Keys.notifyOnSyncErrors) != nil {
            notifyOnSyncErrors = UserDefaults.standard.bool(forKey: Keys.notifyOnSyncErrors)
        } else {
            // Default on; same permission gate as new-episode / download-error alerts.
            notifyOnSyncErrors = true
        }
        if UserDefaults.standard.object(forKey: Keys.askForAppStoreRating) != nil {
            askForAppStoreRating = UserDefaults.standard.bool(forKey: Keys.askForAppStoreRating)
        } else {
            askForAppStoreRating = true
        }
        if UserDefaults.standard.object(forKey: Keys.playVideoAsAudioOnly) != nil {
            playVideoAsAudioOnly = UserDefaults.standard.bool(forKey: Keys.playVideoAsAudioOnly)
        } else {
            // Default off: show video surface when the episode is video.
            playVideoAsAudioOnly = false
        }
        if UserDefaults.standard.object(forKey: Keys.volumeAdaptationEnabled) != nil {
            volumeAdaptationEnabled = UserDefaults.standard.bool(forKey: Keys.volumeAdaptationEnabled)
        } else {
            // Default off: use .default / .moviePlayback session mode (not spokenAudio).
            volumeAdaptationEnabled = false
        }
        if UserDefaults.standard.object(forKey: Keys.skipSilenceEnabled) != nil {
            skipSilenceEnabled = UserDefaults.standard.bool(forKey: Keys.skipSilenceEnabled)
        } else {
            // Default off; preference only — PlaybackService does not skip silence on AVPlayer.
            skipSilenceEnabled = false
        }
        let chartsRaw = UserDefaults.standard.string(forKey: Keys.chartsCountryCode) ?? "auto"
        chartsCountryCode = ChartsCountryPreference.fromStorage(chartsRaw).storageValue
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

    private static func loadSkipSeconds(key: String, defaultValue: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        let stored = UserDefaults.standard.integer(forKey: key)
        return skipIntervalPresets.contains(stored) ? stored : defaultValue
    }

    private static func loadSkipIntroOutroSeconds(key: String) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultSkipIntroOutroSeconds
        }
        let stored = UserDefaults.standard.integer(forKey: key)
        return skipIntroOutroPresets.contains(stored) ? stored : defaultSkipIntroOutroSeconds
    }

    /// Label for Settings pickers (`Off` when 0).
    static func skipIntroOutroLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds) seconds"
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

    // MARK: - Data backup

    /// Snapshot of UserDefaults-backed prefs for iOS JSON backup (no Keychain).
    func backupSnapshot() -> AppSettingsBackupSnapshot {
        let storageKind: String
        let storageValue: Int?
        switch downloadStorageLimit {
        case .unlimited:
            storageKind = Kind.unlimited.rawValue
            storageValue = nil
        case .gigabytes(let gb):
            storageKind = Kind.gigabytes.rawValue
            storageValue = gb
        case .customMegabytes(let mb):
            storageKind = Kind.customMegabytes.rawValue
            storageValue = mb
        }
        return AppSettingsBackupSnapshot(
            theme: theme.rawValue,
            defaultPlaybackSpeed: defaultPlaybackSpeed,
            storageLimitKind: storageKind,
            storageLimitValue: storageValue,
            refreshInterval: refreshInterval.rawValue,
            lastFeedRefreshAtEpoch: lastFeedRefreshAt?.timeIntervalSince1970,
            newEpisodeAction: newEpisodeAction.rawValue,
            autoDownloadEnabled: autoDownloadEnabled,
            autoDownloadEpisodesPerFeed: autoDownloadEpisodesPerFeed.rawValue,
            autoDownloadWifiOnly: autoDownloadWifiOnly,
            manualDownloadWifiOnly: manualDownloadWifiOnly,
            streamWifiOnly: streamWifiOnly,
            playbackSourcePreference: playbackSourcePreference.rawValue,
            autoDeleteAfterPlaying: autoDeleteAfterPlaying,
            rewindSeconds: rewindSeconds,
            fastForwardSeconds: fastForwardSeconds,
            skipIntroSeconds: skipIntroSeconds,
            skipOutroSeconds: skipOutroSeconds,
            notifyOnNewEpisodes: notifyOnNewEpisodes,
            notifyOnDownloadErrors: notifyOnDownloadErrors,
            notifyOnSyncErrors: notifyOnSyncErrors,
            askForAppStoreRating: askForAppStoreRating,
            playVideoAsAudioOnly: playVideoAsAudioOnly,
            volumeAdaptationEnabled: volumeAdaptationEnabled,
            skipSilenceEnabled: skipSilenceEnabled,
            chartsCountryCode: chartsCountryCode
        )
    }

    /// Apply prefs from an iOS JSON backup (writes through didSet → UserDefaults).
    func applyBackupSnapshot(_ snap: AppSettingsBackupSnapshot) {
        theme = AppTheme(rawValue: snap.theme) ?? .system
        if AppSettings.speedPresets.contains(snap.defaultPlaybackSpeed) {
            defaultPlaybackSpeed = snap.defaultPlaybackSpeed
        }
        switch Kind(rawValue: snap.storageLimitKind) {
        case .unlimited, .none:
            downloadStorageLimit = .unlimited
        case .gigabytes:
            let gb = snap.storageLimitValue ?? 5
            downloadStorageLimit = .gigabytes([1, 5, 10].contains(gb) ? gb : 5)
        case .customMegabytes:
            let mb = snap.storageLimitValue ?? 500
            downloadStorageLimit = .customMegabytes(mb)
        }
        refreshInterval = FeedRefreshInterval(rawValue: snap.refreshInterval) ?? .manual
        if let epoch = snap.lastFeedRefreshAtEpoch {
            lastFeedRefreshAt = Date(timeIntervalSince1970: epoch)
        } else {
            lastFeedRefreshAt = nil
        }
        newEpisodeAction = NewEpisodeAction(rawValue: snap.newEpisodeAction ?? "") ?? .inboxOnly
        autoDownloadEnabled = snap.autoDownloadEnabled
        autoDownloadEpisodesPerFeed =
            AutoDownloadEpisodesPerFeed(rawValue: snap.autoDownloadEpisodesPerFeed) ?? .two
        autoDownloadWifiOnly = snap.autoDownloadWifiOnly
        manualDownloadWifiOnly = snap.manualDownloadWifiOnly
        streamWifiOnly = snap.streamWifiOnly
        playbackSourcePreference =
            PlaybackSourcePreference(rawValue: snap.playbackSourcePreference) ?? .automatic
        autoDeleteAfterPlaying = snap.autoDeleteAfterPlaying
        if AppSettings.skipIntervalPresets.contains(snap.rewindSeconds) {
            rewindSeconds = snap.rewindSeconds
        }
        if AppSettings.skipIntervalPresets.contains(snap.fastForwardSeconds) {
            fastForwardSeconds = snap.fastForwardSeconds
        }
        if AppSettings.skipIntroOutroPresets.contains(snap.skipIntroSeconds) {
            skipIntroSeconds = snap.skipIntroSeconds
        }
        if AppSettings.skipIntroOutroPresets.contains(snap.skipOutroSeconds) {
            skipOutroSeconds = snap.skipOutroSeconds
        }
        notifyOnNewEpisodes = snap.notifyOnNewEpisodes
        notifyOnDownloadErrors = snap.notifyOnDownloadErrors
        notifyOnSyncErrors = snap.notifyOnSyncErrors ?? true
        askForAppStoreRating = snap.askForAppStoreRating ?? true
        playVideoAsAudioOnly = snap.playVideoAsAudioOnly ?? false
        volumeAdaptationEnabled = snap.volumeAdaptationEnabled ?? false
        skipSilenceEnabled = snap.skipSilenceEnabled ?? false
        chartsCountryCode = ChartsCountryPreference.fromStorage(snap.chartsCountryCode).storageValue
    }
}

/// Codable prefs blob inside `app-settings.json` backup entry.
struct AppSettingsBackupSnapshot: Codable, Equatable {
    var theme: String
    var defaultPlaybackSpeed: Float
    var storageLimitKind: String
    var storageLimitValue: Int?
    var refreshInterval: String
    var lastFeedRefreshAtEpoch: Double?
    var newEpisodeAction: String?
    var autoDownloadEnabled: Bool
    var autoDownloadEpisodesPerFeed: Int
    var autoDownloadWifiOnly: Bool
    var manualDownloadWifiOnly: Bool
    var streamWifiOnly: Bool
    var playbackSourcePreference: String
    var autoDeleteAfterPlaying: Bool
    var rewindSeconds: Int
    var fastForwardSeconds: Int
    var skipIntroSeconds: Int
    var skipOutroSeconds: Int
    var notifyOnNewEpisodes: Bool
    var notifyOnDownloadErrors: Bool
    /// Absent in older backups → treated as on (default).
    var notifyOnSyncErrors: Bool? = true
    /// Absent in older backups → treated as on (default).
    var askForAppStoreRating: Bool? = true
    /// Absent in older backups → treated as off (show video when detected).
    var playVideoAsAudioOnly: Bool? = false
    /// Absent in older backups → treated as off (default / moviePlayback session mode).
    var volumeAdaptationEnabled: Bool? = false
    /// Absent in older backups → treated as off (preference only; no AVPlayer skip).
    var skipSilenceEnabled: Bool? = false
    var chartsCountryCode: String
}
