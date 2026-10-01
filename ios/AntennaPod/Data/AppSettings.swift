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

/// User preferences for P0 Settings (theme + default playback speed).
@MainActor
final class AppSettings: ObservableObject {
    static let speedPresets: [Float] = [0.8, 1.0, 1.2, 1.5, 2.0]

    private enum Keys {
        static let theme = "settings.theme"
        static let defaultPlaybackSpeed = "settings.defaultPlaybackSpeed"
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

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.system.rawValue
        theme = AppTheme(rawValue: themeRaw) ?? .system
        if UserDefaults.standard.object(forKey: Keys.defaultPlaybackSpeed) != nil {
            let stored = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
            defaultPlaybackSpeed = Self.speedPresets.contains(stored) ? stored : 1.0
        } else {
            defaultPlaybackSpeed = 1.0
        }
    }
}
