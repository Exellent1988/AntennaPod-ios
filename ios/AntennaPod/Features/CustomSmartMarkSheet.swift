import SwiftUI

/// Compact sheet: set a custom smart mark-as-played threshold (1–600 seconds).
/// Writes `AppSettings.smartMarkAsPlayedSeconds` (UserDefaults + backup).
/// `PlaybackService.almostEnded` already reads that setting on leave/stop.
struct CustomSmartMarkSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var secondsText: String

    private var range: ClosedRange<Int> { PlaybackService.customSmartMarkAsPlayedSecondsRange }

    init(initialSeconds: Int) {
        let r = PlaybackService.customSmartMarkAsPlayedSecondsRange
        // Off (0) is Settings preset-only; seed Custom… with default 30 when opening from Off.
        let seed = initialSeconds == 0 ? AppSettings.defaultSmartMarkAsPlayedSeconds : initialSeconds
        let clamped = min(max(seed, r.lowerBound), r.upperBound)
        _secondsText = State(initialValue: String(clamped))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Seconds"), text: $secondsText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel(String(localized: "Seconds"))
                        .accessibilityValue(thresholdAccessibilityValue)
                        .accessibilityHint(
                            String(localized: "Enter a whole number from 1 to 600 seconds remaining. The Set button stays unavailable until the value is valid.")
                        )

                    if !isValid {
                        Text(String(localized: "Enter a whole number from 1 to 600 seconds."))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                    }

                    Stepper(value: Binding(
                        get: {
                            if let parsed = parsedSeconds {
                                return min(max(parsed, range.lowerBound), range.upperBound)
                            }
                            let seed = settings.smartMarkAsPlayedSeconds == 0
                                ? AppSettings.defaultSmartMarkAsPlayedSeconds
                                : settings.smartMarkAsPlayedSeconds
                            return min(max(seed, range.lowerBound), range.upperBound)
                        },
                        set: { secondsText = String($0) }
                    ), in: range) {
                        if let seconds = parsedSeconds, range.contains(seconds) {
                            Text(AppSettings.smartMarkAsPlayedLabel(seconds))
                        } else {
                            Text(String(localized: "Seconds"))
                        }
                    }
                    .accessibilityLabel(String(localized: "Seconds"))
                    .accessibilityValue(stepperAccessibilityValue)
                    .accessibilityHint(
                        String(localized: "Adjusts the threshold in one-second steps. Valid range is 1 to 600 seconds remaining.")
                    )
                } footer: {
                    Text(String(localized: "Choose between 1 and 600 seconds remaining. Presets (Off / 15 / 30 / 60 / 120 / 300 / 600) stay in Settings. Marks played when leaving or stopping within this window — not a percent threshold."))
                }
            }
            .navigationTitle(String(localized: "Custom smart mark"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Set")) { confirm() }
                        .disabled(!isValid)
                        .accessibilityHint(String(localized: "Saves this threshold for smart mark as played."))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var parsedSeconds: Int? {
        Int(secondsText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var thresholdAccessibilityValue: String {
        guard let seconds = parsedSeconds, range.contains(seconds) else {
            return secondsText.isEmpty ? String(localized: "No threshold entered") : secondsText
        }
        return AppSettings.smartMarkAsPlayedLabel(seconds)
    }

    private var stepperAccessibilityValue: String {
        let seconds = parsedSeconds.map { min(max($0, range.lowerBound), range.upperBound) }
            ?? min(max(settings.smartMarkAsPlayedSeconds == 0 ? AppSettings.defaultSmartMarkAsPlayedSeconds : settings.smartMarkAsPlayedSeconds, range.lowerBound), range.upperBound)
        return AppSettings.smartMarkAsPlayedLabel(seconds)
    }

    private var isValid: Bool {
        guard let seconds = parsedSeconds else { return false }
        return range.contains(seconds)
    }

    private func confirm() {
        guard let seconds = parsedSeconds, range.contains(seconds) else { return }
        settings.smartMarkAsPlayedSeconds = seconds
        dismiss()
    }
}
