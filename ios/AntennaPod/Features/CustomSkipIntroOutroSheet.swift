import PodcastCore
import SwiftUI

/// Free-seconds entry for Skip intro / Skip ending (Android FeedPreferences accepts any number of
/// seconds). Used by Settings (global default) and per-podcast settings (override).
struct CustomSkipIntroOutroSheet: View {
    enum Kind: String, Identifiable {
        case intro, outro
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    let onSave: (Int) -> Void
    @State private var secondsText: String

    /// Picker tag that opens this sheet instead of selecting a value.
    static let customTag = -1

    init(kind: Kind, initialSeconds: Int, onSave: @escaping (Int) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _secondsText = State(initialValue: String(max(0, initialSeconds)))
    }

    private var parsed: Int? { SkipIntroOutro.normalized(Int(secondsText.trimmingCharacters(in: .whitespaces))) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Seconds"), text: $secondsText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel(String(localized: "Seconds"))
                    Stepper(value: Binding(get: { parsed ?? 0 }, set: { secondsText = String($0) }),
                            in: 0...SkipIntroOutro.maximumSeconds, step: 5) {
                        Text(AppSettings.skipIntroOutroLabel(parsed ?? 0))
                    }
                } footer: {
                    Text(kind == .intro
                         ? String(localized: "Seconds skipped at the start of an episode (0 to 3600). 0 turns it off.")
                         : String(localized: "Seconds skipped at the end of an episode, then the next episode plays (0 to 3600). 0 turns it off."))
                }
            }
            .navigationTitle(kind == .intro ? String(localized: "Skip intro") : String(localized: "Skip outro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Set")) {
                        if let parsed { onSave(parsed) }
                        dismiss()
                    }
                    .disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
