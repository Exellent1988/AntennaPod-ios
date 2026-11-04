import Foundation

/// Android `prefHardwareForwardButton` / `prefHardwarePreviousButton` (`button_action_values`):
/// what a headset / car / lock-screen next or previous button does.
/// Defaults: forward → fast-forward, previous → rewind (Android keycode defaults).
public enum HardwareButtonAction: String, CaseIterable, Codable, Sendable {
    case fastForward
    case rewind
    case skipEpisode
    case restartEpisode

    public static let defaultForward: HardwareButtonAction = .fastForward
    public static let defaultPrevious: HardwareButtonAction = .rewind

    /// Unknown / missing stored values fall back to the button's default.
    public static func resolve(_ raw: String?, default fallback: HardwareButtonAction) -> HardwareButtonAction {
        raw.flatMap(HardwareButtonAction.init(rawValue:)) ?? fallback
    }
}
