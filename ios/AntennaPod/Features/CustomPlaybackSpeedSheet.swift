import SwiftUI

/// Compact sheet: pick a custom playback speed (0.50×–3.00×, 0.05 steps), then
/// `PlaybackService.setRate` (session), `AppSettings.defaultPlaybackSpeed`, and/or
/// per-feed override in `feed-settings.json`.
/// Stock AVPlayer — not Android ExoPlayer; quality may degrade above ~2×.
struct CustomPlaybackSpeedSheet: View {
    enum Mode {
        /// Apply via `PlaybackService.setRate` (current session only unless toggle).
        case session
        /// Persist Settings default only — does **not** change the rate already playing.
        case defaultSpeed
        /// Persist per-feed override; also reapplies if an episode from that feed is playing.
        case feedOverride
    }

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    /// Required when `mode == .feedOverride`: writes clamped speed into feed settings.
    var onConfirmFeedOverride: ((Float) -> Void)? = nil

    @State private var speedText: String
    @State private var alsoSetAsDefault = false

    private var range: ClosedRange<Float> { PlaybackService.customPlaybackSpeedRange }
    private var step: Float { PlaybackService.customPlaybackSpeedStep }

    init(mode: Mode, initialSpeed: Float, onConfirmFeedOverride: ((Float) -> Void)? = nil) {
        self.mode = mode
        self.onConfirmFeedOverride = onConfirmFeedOverride
        let clamped = PlaybackService.clampPlaybackSpeed(initialSpeed)
        _speedText = State(initialValue: Self.fieldText(for: clamped))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Speed"), text: $speedText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(String(localized: "Playback speed"))
                        .accessibilityValue(speedFieldAccessibilityValue)
                        .accessibilityHint(String(localized: "Enter a playback speed from 0.50× to 3.00×. Slider and Stepper use 0.05 steps."))

                    Slider(
                        value: Binding(
                            get: { parsedOrFallback },
                            set: { speedText = Self.fieldText(for: PlaybackService.clampPlaybackSpeed($0)) }
                        ),
                        in: range,
                        step: step
                    )
                    .accessibilityLabel(String(localized: "Playback speed"))
                    .accessibilityValue(PlaybackService.formatPlaybackSpeed(parsedOrFallback))
                    .accessibilityHint(String(localized: "Adjusts playback speed in 0.05 increments"))

                    Stepper(value: Binding(
                        get: { parsedOrFallback },
                        set: { speedText = Self.fieldText(for: PlaybackService.clampPlaybackSpeed($0)) }
                    ), in: range, step: step) {
                        Text(PlaybackService.formatPlaybackSpeed(parsedOrFallback))
                            .monospacedDigit()
                    }
                    .accessibilityLabel(String(localized: "Playback speed"))
                    .accessibilityValue(PlaybackService.formatPlaybackSpeed(parsedOrFallback))
                    .accessibilityHint(String(localized: "Adjusts playback speed in 0.05 increments"))

                    if mode == .session {
                        Toggle(String(localized: "Also set as default"), isOn: $alsoSetAsDefault)
                            .accessibilityHint(String(localized: "Also saves this value as the global default playback speed"))
                    }
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Set")) { confirm() }
                        .disabled(!isValid)
                        .accessibilityLabel(String(localized: "Set playback speed"))
                        .accessibilityHint(setAccessibilityHint)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var navigationTitle: String {
        switch mode {
        case .session:
            return String(localized: "Custom playback speed")
        case .defaultSpeed:
            return String(localized: "Custom default speed")
        case .feedOverride:
            return String(localized: "Custom feed playback speed")
        }
    }

    private var footerText: String {
        switch mode {
        case .session:
            return String(localized: "Applies to the current session only (0.50×–3.00×, 0.05 steps) unless Also set as default is on. Stock AVPlayer — quality may degrade above ~2×. Not Android ExoPlayer.")
        case .defaultSpeed:
            return String(localized: "New episodes start at this speed (0.50×–3.00×, 0.05 steps). Does not change the rate of what’s already playing. Stock AVPlayer — quality may degrade above ~2×.")
        case .feedOverride:
            return String(localized: "This podcast’s episodes use this speed (0.50×–3.00×, 0.05 steps). Applied on a fresh episode start and immediately if an episode from this podcast is already playing. Does not rewrite the player’s session rate from every tap — only this Feed setting (and Custom…) persists per feed. Stock AVPlayer — quality may degrade above ~2×.")
        }
    }

    private var speedFieldAccessibilityValue: String {
        guard let value = parsedSpeed, range.contains(value) else { return speedText }
        return PlaybackService.formatPlaybackSpeed(value)
    }

    private var setAccessibilityHint: String {
        guard isValid else {
            return String(localized: "Enter a playback speed from 0.50× to 3.00× before setting")
        }
        switch mode {
        case .session:
            return alsoSetAsDefault
                ? String(localized: "Sets the current playback speed and the global default")
                : String(localized: "Sets the current playback speed for this session")
        case .defaultSpeed:
            return String(localized: "Sets the default playback speed for new episodes")
        case .feedOverride:
            return String(localized: "Sets this podcast's playback speed for new episodes and the currently playing episode from this podcast")
        }
    }

    private var parsedSpeed: Float? {
        let trimmed = speedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Float(trimmed) else { return nil }
        return value
    }

    private var parsedOrFallback: Float {
        if let value = parsedSpeed {
            return PlaybackService.clampPlaybackSpeed(value)
        }
        return 1.0
    }

    private var isValid: Bool {
        guard let value = parsedSpeed else { return false }
        return range.contains(value)
    }

    private func confirm() {
        guard let value = parsedSpeed else { return }
        let clamped = PlaybackService.clampPlaybackSpeed(value)
        switch mode {
        case .session:
            playback.setRate(clamped)
            if alsoSetAsDefault {
                settings.defaultPlaybackSpeed = clamped
            }
        case .defaultSpeed:
            settings.defaultPlaybackSpeed = clamped
        case .feedOverride:
            onConfirmFeedOverride?(clamped)
        }
        dismiss()
    }

    private static func fieldText(for speed: Float) -> String {
        String(format: "%.2f", speed)
    }
}
