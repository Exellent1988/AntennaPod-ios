import Foundation
import SwiftUI

/// Parental controls (beta MVP): PIN in Keychain; option flags in UserDefaults; session unlock in memory.
/// Session unlock lasts until the app backgrounds (`scenePhase` → inactive/background).
@MainActor
final class ParentalControls: ObservableObject {
    private enum Keys {
        static let enabled = "settings.parental.enabled"
        static let lockAddDiscover = "settings.parental.lockAddDiscover"
        static let lockNetworkDownloads = "settings.parental.lockNetworkDownloads"
        static let hideExplicitCharts = "settings.parental.hideExplicitCharts"
    }

    /// Master switch. Enabling requires a PIN; disabling clears Keychain after PIN verify.
    @Published private(set) var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
        }
    }

    /// Require PIN to open Add sheet / Discover (charts). Default on when enabled.
    @Published var lockAddDiscover: Bool {
        didSet {
            UserDefaults.standard.set(lockAddDiscover, forKey: Keys.lockAddDiscover)
        }
    }

    /// Require PIN to change Network / Downloads Wi‑Fi toggles. Default off.
    @Published var lockNetworkDownloadsSettings: Bool {
        didSet {
            UserDefaults.standard.set(lockNetworkDownloadsSettings, forKey: Keys.lockNetworkDownloads)
        }
    }

    /// When parental controls are enabled, request iTunes charts with `explicit=false`. Default off.
    @Published var hideExplicitCharts: Bool {
        didSet {
            UserDefaults.standard.set(hideExplicitCharts, forKey: Keys.hideExplicitCharts)
        }
    }

    /// In-memory session unlock after a successful PIN entry. Cleared on background.
    @Published private(set) var isSessionUnlocked = false

    /// True when parental controls are on and the session has not been unlocked.
    var isLocked: Bool {
        isEnabled && !isSessionUnlocked
    }

    /// Gate Add sheet / Discover navigation.
    var needsPINForAddDiscover: Bool {
        isLocked && lockAddDiscover
    }

    /// Gate Network / Downloads settings edits.
    var needsPINForNetworkDownloads: Bool {
        isLocked && lockNetworkDownloadsSettings
    }

    /// Charts should omit explicit content while parental controls are enabled and the option is on
    /// (not session-dependent — content filter stays on until parental controls are disabled).
    var shouldHideExplicitCharts: Bool {
        isEnabled && hideExplicitCharts
    }

    var hasPIN: Bool {
        ParentalControlsKeychain.hasPIN
    }

    init() {
        let pinPresent = ParentalControlsKeychain.hasPIN
        let storedEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? false
        // Enabled only if a PIN exists (honest if Keychain was wiped).
        isEnabled = storedEnabled && pinPresent
        if UserDefaults.standard.object(forKey: Keys.lockAddDiscover) != nil {
            lockAddDiscover = UserDefaults.standard.bool(forKey: Keys.lockAddDiscover)
        } else {
            lockAddDiscover = true
        }
        if UserDefaults.standard.object(forKey: Keys.lockNetworkDownloads) != nil {
            lockNetworkDownloadsSettings = UserDefaults.standard.bool(forKey: Keys.lockNetworkDownloads)
        } else {
            lockNetworkDownloadsSettings = false
        }
        if UserDefaults.standard.object(forKey: Keys.hideExplicitCharts) != nil {
            hideExplicitCharts = UserDefaults.standard.bool(forKey: Keys.hideExplicitCharts)
        } else {
            hideExplicitCharts = false
        }
        if !pinPresent && storedEnabled {
            UserDefaults.standard.set(false, forKey: Keys.enabled)
        }
    }

    /// Call when `scenePhase` leaves `.active` so gated UI needs PIN again.
    func lockSession() {
        guard isSessionUnlocked else { return }
        isSessionUnlocked = false
    }

    /// Verify PIN and unlock the current session.
    @discardableResult
    func unlockSession(with pin: String) -> Bool {
        guard isEnabled, ParentalControlsKeychain.verifyPIN(pin) else { return false }
        isSessionUnlocked = true
        return true
    }

    /// Enable parental controls with a new PIN (must already be validated 4–6 digits).
    func enable(pin: String) throws {
        try ParentalControlsKeychain.savePIN(pin)
        isEnabled = true
        isSessionUnlocked = true
    }

    /// Change PIN; requires current PIN. Keeps options; leaves session unlocked.
    func changePIN(current: String, newPIN: String) throws {
        guard ParentalControlsKeychain.verifyPIN(current) else {
            throw ParentalControlsError.wrongPIN
        }
        try ParentalControlsKeychain.savePIN(newPIN)
        isSessionUnlocked = true
    }

    /// Disable: verify PIN, clear Keychain, turn off master switch, clear session.
    func disable(pin: String) throws {
        guard ParentalControlsKeychain.verifyPIN(pin) else {
            throw ParentalControlsError.wrongPIN
        }
        ParentalControlsKeychain.deletePIN()
        isEnabled = false
        isSessionUnlocked = false
    }

    enum ParentalControlsError: LocalizedError {
        case wrongPIN

        var errorDescription: String? {
            switch self {
            case .wrongPIN:
                return String(localized: "Incorrect PIN")
            }
        }
    }
}
