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

/// User preferences for P0 Settings (theme, default playback speed, download storage limit).
@MainActor
final class AppSettings: ObservableObject {
    static let speedPresets: [Float] = [0.8, 1.0, 1.2, 1.5, 2.0]
    static let customStorageMBRange = 50...100_000

    private enum Keys {
        static let theme = "settings.theme"
        static let defaultPlaybackSpeed = "settings.defaultPlaybackSpeed"
        static let storageLimitKind = "settings.storageLimit.kind"
        static let storageLimitValue = "settings.storageLimit.value"
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
