import SwiftUI

/// Compact sheet: enter a custom sleep-timer duration (1–180 minutes), then
/// `PlaybackService.setSleepTimer(minutes:)`. Fade behavior unchanged.
struct CustomSleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    @State private var minutesText: String

    private var range: ClosedRange<Int> { PlaybackService.customSleepTimerMinutesRange }

    init(initialMinutes: Int = 30) {
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
                        .accessibilityLabel(String(localized: "Minutes"))

                    Stepper(value: Binding(
                        get: { parsedMinutes.map { min(max($0, range.lowerBound), range.upperBound) } ?? 30 },
                        set: { minutesText = String($0) }
                    ), in: range) {
                        if let minutes = parsedMinutes, range.contains(minutes) {
                            Text(String(localized: "\(minutes) min"))
                        } else {
                            Text(String(localized: "Minutes"))
                        }
                    }
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
                }
            }
        }
        .presentationDetents([.medium])
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
        playback.setSleepTimer(minutes: minutes)
        dismiss()
    }
}
