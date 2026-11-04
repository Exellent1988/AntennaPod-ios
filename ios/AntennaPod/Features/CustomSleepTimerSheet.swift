import SwiftUI

/// Compact sheet: enter a custom sleep-timer duration (1–180 minutes), then
/// `PlaybackService.setSleepTimer(minutes:)`. Remembers the last Custom… value in
/// `AppSettings.lastCustomSleepTimerMinutes` (Android LastValue honesty). Fade unchanged.
struct CustomSleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var minutesText: String

    private var range: ClosedRange<Int> { PlaybackService.customSleepTimerMinutesRange }

    init(initialMinutes: Int = AppSettings.defaultLastCustomSleepTimerMinutes) {
        let r = PlaybackService.customSleepTimerMinutesRange
        let clamped = min(max(initialMinutes, r.lowerBound), r.upperBound)
        _minutesText = State(initialValue: String(clamped))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Minutes"), text: $minutesText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel(String(localized: "Sleep timer minutes"))
                        .accessibilityHint(String(localized: "Enter a whole number from 1 to 180 minutes"))

                    Stepper(value: Binding(
                        get: { parsedMinutes.map { min(max($0, range.lowerBound), range.upperBound) } ?? settings.lastCustomSleepTimerMinutes },
                        set: { minutesText = String($0) }
                    ), in: range) {
                        if let minutes = parsedMinutes, range.contains(minutes) {
                            Text(String(localized: "\(minutes) min"))
                        } else {
                            Text(String(localized: "Minutes"))
                        }
                    }
                    .accessibilityLabel(String(localized: "Sleep timer duration"))
                    .accessibilityValue(String(localized: "\(effectiveMinutesForAccessibility) minutes"))
                    .accessibilityHint(String(localized: "Adjusts the clock sleep timer duration; the value is remembered for the next Custom sleep timer"))
                } footer: {
                    Text(String(localized: "Choose between 1 and 180 minutes."))
                }
            }
            .navigationTitle(String(localized: "Custom sleep timer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Set")) { confirm() }
                        .disabled(!isValid)
                        .accessibilityLabel(String(localized: "Set sleep timer"))
                        .accessibilityHint(setAccessibilityHint)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var effectiveMinutesForAccessibility: Int {
        guard let parsedMinutes else { return settings.lastCustomSleepTimerMinutes }
        return min(max(parsedMinutes, range.lowerBound), range.upperBound)
    }

    private var setAccessibilityHint: String {
        guard let minutes = parsedMinutes, range.contains(minutes) else {
            return String(localized: "Enter a whole number from 1 to 180 minutes before setting the timer")
        }
        return String(localized: "Starts a clock sleep timer for \(minutes) minutes and remembers this value for the next Custom sleep timer")
    }

    private var parsedMinutes: Int? {
        Int(minutesText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isValid: Bool {
        guard let minutes = parsedMinutes else { return false }
        return range.contains(minutes)
    }

    private func confirm() {
        guard let minutes = parsedMinutes, range.contains(minutes) else { return }
        settings.lastCustomSleepTimerMinutes = minutes
        playback.setSleepTimer(minutes: minutes)
        dismiss()
    }
}
