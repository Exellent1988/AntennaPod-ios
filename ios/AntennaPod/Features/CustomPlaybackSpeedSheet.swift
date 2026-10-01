import SwiftUI

/// Compact sheet: pick a custom playback speed (0.50×–3.00×, 0.05 steps), then
/// `PlaybackService.setRate` (session) and/or `AppSettings.defaultPlaybackSpeed`.
/// Stock AVPlayer — not Android ExoPlayer; quality may degrade above ~2×.
struct CustomPlaybackSpeedSheet: View {
    enum Mode {
        /// Apply via `PlaybackService.setRate` (current session only unless toggle).
        case session
        /// Persist Settings default only — does **not** change the rate already playing.
        case defaultSpeed
    }

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var speedText: String
    @State private var alsoSetAsDefault = false

    private var range: ClosedRange<Float> { PlaybackService.customPlaybackSpeedRange }
    private var step: Float { PlaybackService.customPlaybackSpeedStep }

    init(mode: Mode, initialSpeed: Float) {
        self.mode = mode
        let clamped = PlaybackService.clampPlaybackSpeed(initialSpeed)
        _speedText = State(initialValue: Self.fieldText(for: clamped))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Speed"), text: $speedText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(String(localized: "Speed"))

                    Slider(
                        value: Binding(
                            get: { parsedOrFallback },
                            set: { speedText = Self.fieldText(for: PlaybackService.clampPlaybackSpeed($0)) }
                        ),
                        in: range,
                        step: step
                    )
                    .accessibilityLabel(String(localized: "Speed"))
                    .accessibilityValue(PlaybackService.formatPlaybackSpeed(parsedOrFallback))

                    Stepper(value: Binding(
                        get: { parsedOrFallback },
                        set: { speedText = Self.fieldText(for: PlaybackService.clampPlaybackSpeed($0)) }
                    ), in: range, step: step) {
                        Text(PlaybackService.formatPlaybackSpeed(parsedOrFallback))
                            .monospacedDigit()
                    }

                    if mode == .session {
                        Toggle(String(localized: "Also set as default"), isOn: $alsoSetAsDefault)
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
        }
    }

    private var footerText: String {
        switch mode {
        case .session:
            return String(localized: "Applies to the current session only (0.50×–3.00×, 0.05 steps) unless Also set as default is on. Stock AVPlayer — quality may degrade above ~2×. Not Android ExoPlayer.")
        case .defaultSpeed:
            return String(localized: "New episodes start at this speed (0.50×–3.00×, 0.05 steps). Does not change the rate of what’s already playing. Stock AVPlayer — quality may degrade above ~2×.")
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
        }
        dismiss()
    }

    private static func fieldText(for speed: Float) -> String {
        String(format: "%.2f", speed)
    }
}
