import SwiftUI

/// Compact sheet: set a custom rewind or fast-forward skip interval (5–60 seconds).
/// Writes `AppSettings.rewindSeconds` / `fastForwardSeconds` (UserDefaults + backup).
/// Mini / full player and Lockscreen remotes already read those settings.
struct CustomSkipIntervalSheet: View {
    enum Mode: String, Identifiable {
        case rewind
        case fastForward

        var id: String { rawValue }
    }

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var secondsText: String

    private var range: ClosedRange<Int> { PlaybackService.customSkipIntervalSecondsRange }

    init(mode: Mode, initialSeconds: Int) {
        self.mode = mode
        let r = PlaybackService.customSkipIntervalSecondsRange
        let clamped = min(max(initialSeconds, r.lowerBound), r.upperBound)
        _secondsText = State(initialValue: String(clamped))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Seconds"), text: $secondsText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel(String(localized: "Seconds"))
                        .accessibilityValue(secondsFieldAccessibilityValue)
                        .accessibilityHint(String(localized: "Enter a whole number from 5 to 60 seconds"))

                    Stepper(value: Binding(
                        get: {
                            parsedSeconds.map { min(max($0, range.lowerBound), range.upperBound) }
                                ?? (mode == .rewind ? settings.rewindSeconds : settings.fastForwardSeconds)
                        },
                        set: { secondsText = String($0) }
                    ), in: range) {
                        if let seconds = parsedSeconds, range.contains(seconds) {
                            Text(AppSettings.skipIntervalLabel(seconds))
                        } else {
                            Text(String(localized: "Seconds"))
                        }
                    }
                    .accessibilityLabel(String(localized: "Seconds"))
                    .accessibilityValue(stepperAccessibilityValue)
                    .accessibilityHint(String(localized: "Adjusts the custom skip interval in one-second steps"))
                } footer: {
                    Text(String(localized: "Choose between 5 and 60 seconds. Presets stay available in Settings; custom values work the same for mini player, full player, and Lockscreen / Now Playing."))
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
                        .accessibilityLabel(String(localized: "Set skip interval"))
                        .accessibilityHint(String(localized: "Saves this custom interval for the selected rewind or fast-forward action"))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var navigationTitle: String {
        switch mode {
        case .rewind:
            return String(localized: "Custom rewind")
        case .fastForward:
            return String(localized: "Custom fast-forward")
        }
    }

    private var parsedSeconds: Int? {
        Int(secondsText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isValid: Bool {
        guard let seconds = parsedSeconds else { return false }
        return range.contains(seconds)
    }

    private var secondsFieldAccessibilityValue: String {
        guard let seconds = parsedSeconds, range.contains(seconds) else {
            return String(localized: "Invalid — enter 5 to 60 seconds")
        }
        return AppSettings.skipIntervalLabel(seconds)
    }

    private var stepperAccessibilityValue: String {
        let seconds = parsedSeconds.map { min(max($0, range.lowerBound), range.upperBound) }
            ?? (mode == .rewind ? settings.rewindSeconds : settings.fastForwardSeconds)
        return AppSettings.skipIntervalLabel(seconds)
    }

    private func confirm() {
        guard let seconds = parsedSeconds, range.contains(seconds) else { return }
        switch mode {
        case .rewind:
            settings.rewindSeconds = seconds
        case .fastForward:
            settings.fastForwardSeconds = seconds
        }
        dismiss()
    }
}
