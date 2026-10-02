import SwiftUI

/// Compact sheet: enter a playback position (mm:ss text or minutes + seconds
/// steppers), clamp to `[0, duration]`, then `PlaybackService.seek(toSeconds:)`.
struct JumpToPositionSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    @State private var timeText: String
    @State private var minutes: Int
    @State private var seconds: Int
    /// Avoid feedback loops when steppers rewrite text (and vice versa).
    @State private var isSyncing = false

    init(initialSeconds: Double = 0) {
        let total = max(0, Int(initialSeconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        _minutes = State(initialValue: m)
        _seconds = State(initialValue: s)
        _timeText = State(initialValue: JumpToPositionSheet.formatTime(minutes: m, seconds: s))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "mm:ss"), text: $timeText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(String(localized: "Position"))
                        .accessibilityValue(positionFieldAccessibilityValue)
                        .accessibilityHint(String(localized: "Enter time as mm:ss or minutes and seconds. The Jump button stays unavailable until duration is known and the value can be parsed."))
                        .onChange(of: timeText) { _, newValue in
                            guard !isSyncing else { return }
                            if let parsed = Self.parseTime(newValue) {
                                let capped = min(parsed, max(0, Int(maxDurationSeconds.rounded(.down))))
                                isSyncing = true
                                minutes = min(capped / 60, maxMinutes)
                                seconds = capped % 60
                                isSyncing = false
                            }
                        }

                    Stepper(value: $minutes, in: 0...maxMinutes) {
                        Text(String(localized: "\(minutes) min"))
                    }
                    .accessibilityLabel(String(localized: "Minutes"))
                    .accessibilityValue(minutesAccessibilityValue)
                    .accessibilityHint(String(localized: "Adjusts the jump minutes. Seconds stay separate; the position is clamped to the episode duration."))
                    .onChange(of: minutes) { _, _ in
                        syncTextFromSteppers()
                    }

                    Stepper(value: $seconds, in: 0...59) {
                        Text(String(localized: "\(seconds) sec"))
                    }
                    .accessibilityLabel(String(localized: "Seconds"))
                    .accessibilityValue(secondsAccessibilityValue)
                    .accessibilityHint(String(localized: "Adjusts the jump seconds from 0 to 59. Combined with minutes, the position is clamped to the episode duration."))
                    .onChange(of: seconds) { _, _ in
                        syncTextFromSteppers()
                    }
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle(String(localized: "Jump to position"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Jump")) { confirm() }
                        .disabled(!isValid)
                        .accessibilityLabel(String(localized: "Jump to position"))
                        .accessibilityHint(jumpAccessibilityHint)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var maxDurationSeconds: Double {
        let d = playback.durationSeconds
        guard d.isFinite, d > 0 else { return 0 }
        return d
    }

    private var maxMinutes: Int {
        max(0, Int(maxDurationSeconds.rounded(.down)) / 60)
    }

    private var parsedTotalSeconds: Int? {
        if let fromText = Self.parseTime(timeText) {
            return fromText
        }
        // Fall back to steppers when text is mid-edit / empty.
        return minutes * 60 + seconds
    }

    private var isValid: Bool {
        guard maxDurationSeconds > 0, parsedTotalSeconds != nil else { return false }
        return true
    }

    private var footerText: String {
        guard maxDurationSeconds > 0 else {
            return String(localized: "Duration unknown — jump unavailable.")
        }
        let end = Self.formatTime(
            minutes: Int(maxDurationSeconds) / 60,
            seconds: Int(maxDurationSeconds) % 60
        )
        return String(localized: "Clamped to 0…\(end) (episode duration).")
    }

    private var positionFieldAccessibilityValue: String {
        guard maxDurationSeconds > 0 else {
            return String(localized: "Duration unknown — jump unavailable.")
        }
        if let fromText = Self.parseTime(timeText) {
            let capped = min(max(0, fromText), Int(maxDurationSeconds.rounded(.down)))
            return Self.formatTime(minutes: capped / 60, seconds: capped % 60)
        }
        let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.formatTime(minutes: minutes, seconds: seconds)
        }
        return String(localized: "Invalid — enter mm:ss or minutes and seconds")
    }

    private var minutesAccessibilityValue: String {
        String(localized: "\(minutes) min")
    }

    private var secondsAccessibilityValue: String {
        String(localized: "\(seconds) sec")
    }

    private var jumpAccessibilityHint: String {
        guard maxDurationSeconds > 0 else {
            return String(localized: "Jump stays unavailable until the episode duration is known.")
        }
        guard isValid else {
            return String(localized: "Enter a valid time as mm:ss or use the minutes and seconds steppers.")
        }
        return String(localized: "Seeks to the entered position, clamped to the episode duration.")
    }

    private func syncTextFromSteppers() {
        guard !isSyncing else { return }
        isSyncing = true
        timeText = Self.formatTime(minutes: minutes, seconds: seconds)
        isSyncing = false
    }

    private func confirm() {
        guard let total = parsedTotalSeconds else { return }
        let clamped = min(max(0, Double(total)), maxDurationSeconds)
        playback.seek(toSeconds: clamped)
        dismiss()
    }

    /// Formats as `m:ss` (or `h:mm:ss` when ≥ 60 min).
    static func formatTime(minutes: Int, seconds: Int) -> String {
        let total = max(0, minutes) * 60 + max(0, min(59, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Parses `m:ss`, `mm:ss`, `h:mm:ss`, or a plain integer (total seconds).
    static func parseTime(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 || parts.count == 3 else { return nil }
            let ints = parts.compactMap { Int($0) }
            guard ints.count == parts.count else { return nil }
            if ints.count == 2 {
                let m = ints[0]
                let s = ints[1]
                guard m >= 0, s >= 0, s < 60 else { return nil }
                return m * 60 + s
            }
            let h = ints[0]
            let m = ints[1]
            let s = ints[2]
            guard h >= 0, m >= 0, m < 60, s >= 0, s < 60 else { return nil }
            return h * 3600 + m * 60 + s
        }

        // Plain integer → total seconds.
        guard let secondsOnly = Int(trimmed), secondsOnly >= 0 else { return nil }
        return secondsOnly
    }
}
