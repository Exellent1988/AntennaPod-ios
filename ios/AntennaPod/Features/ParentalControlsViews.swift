import SwiftUI

// MARK: - Settings destination

/// Settings → Parental controls (beta MVP).
struct ParentalControlsSettingsView: View {
    @EnvironmentObject private var parental: ParentalControls

    @State private var showSetPIN = false
    @State private var showChangePIN = false
    @State private var showDisablePIN = false
    /// Option toggles change what the PIN protects, so a locked session must enter it first.
    @State private var showOptionsPINGate = false
    @State private var pendingOptionChange: (() -> Void)?
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable parental controls", isOn: enableBinding)
                    .accessibilityHint(enableHelpText)
                if parental.isEnabled {
                    LabeledContent("Status") {
                        Text(parental.isSessionUnlocked ? String(localized: "Unlocked (this session)") : String(localized: "Locked"))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Button("Change PIN") {
                        showChangePIN = true
                    }
                    .accessibilityHint(enableHelpText)
                }
                Text(enableHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Parental controls")
                    .accessibilityAddTraits(.isHeader)
            }

            if parental.isEnabled {
                Section {
                    Toggle("Lock Add / Discover", isOn: gatedOptionToggle(\.lockAddDiscover))
                        .accessibilityHint(optionsHelpText)
                    Toggle("Lock Network / Downloads settings", isOn: gatedOptionToggle(\.lockNetworkDownloadsSettings))
                        .accessibilityHint(optionsHelpText)
                    Toggle("Hide explicit top charts", isOn: gatedOptionToggle(\.hideExplicitCharts))
                        .accessibilityHint(optionsHelpText)
                    Text(optionsHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Options")
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .navigationTitle("Parental controls")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSetPIN) {
            ParentalSetPINSheet(
                title: String(localized: "Set PIN"),
                confirmLabel: String(localized: "Enable"),
                onCancel: {
                    showSetPIN = false
                },
                onSave: { pin in
                    do {
                        try parental.enable(pin: pin)
                        showSetPIN = false
                        statusIsError = false
                        statusMessage = String(localized: "Parental controls enabled. PIN stored in Keychain.")
                    } catch {
                        statusIsError = true
                        statusMessage = error.localizedDescription
                    }
                }
            )
        }
        .sheet(isPresented: $showChangePIN) {
            ParentalChangePINSheet(
                onCancel: { showChangePIN = false },
                onSave: { current, newPIN in
                    try parental.changePIN(current: current, newPIN: newPIN)
                    showChangePIN = false
                    statusIsError = false
                    statusMessage = String(localized: "PIN updated.")
                }
            )
        }
        .sheet(isPresented: $showDisablePIN) {
            ParentalPINPromptSheet(
                title: String(localized: "Disable parental controls"),
                message: String(localized: "Enter your PIN to turn off parental controls and remove the stored PIN."),
                confirmLabel: String(localized: "Disable"),
                onCancel: { showDisablePIN = false },
                onSuccess: { pin in
                    do {
                        try parental.disable(pin: pin)
                        showDisablePIN = false
                        statusIsError = false
                        statusMessage = String(localized: "Parental controls disabled. PIN cleared from Keychain.")
                        return true
                    } catch {
                        return false
                    }
                }
            )
        }
        .sheet(isPresented: $showOptionsPINGate) {
            ParentalPINPromptSheet(
                title: String(localized: "Parental controls"),
                onCancel: {
                    showOptionsPINGate = false
                    pendingOptionChange = nil
                },
                onSuccess: { pin in
                    if parental.unlockSession(with: pin) {
                        showOptionsPINGate = false
                        pendingOptionChange?()
                        pendingOptionChange = nil
                        return true
                    }
                    return false
                }
            )
        }
    }

    /// Binding that asks for the PIN before a locked session changes a parental option.
    private func gatedOptionToggle(_ keyPath: ReferenceWritableKeyPath<ParentalControls, Bool>) -> Binding<Bool> {
        Binding(
            get: { parental[keyPath: keyPath] },
            set: { newValue in
                if parental.isLocked {
                    pendingOptionChange = { parental[keyPath: keyPath] = newValue }
                    showOptionsPINGate = true
                } else {
                    parental[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var enableBinding: Binding<Bool> {
        Binding(
            get: { parental.isEnabled },
            set: { newValue in
                if newValue {
                    if parental.isEnabled { return }
                    showSetPIN = true
                } else {
                    if !parental.isEnabled { return }
                    showDisablePIN = true
                }
            }
        )
    }

    private var enableHelpText: String {
        if parental.isEnabled {
            return String(localized: "PIN is stored in the Keychain (not in Settings backup). Unlock lasts until the app goes to the background. Disable requires the PIN and clears Keychain.")
        }
        return String(localized: "Set a 4–6 digit PIN to restrict Add / Discover and optionally Network / Downloads settings or explicit charts. Beta MVP — not a full device parental lock.")
    }

    private var optionsHelpText: String {
        String(localized: "Lock Add / Discover asks for the PIN before the Add sheet or Discover charts. Lock Network / Downloads blocks Wi‑Fi-only toggles until unlocked. Hide explicit top charts requests iTunes charts with explicit=false while parental controls are enabled.")
    }
}

// MARK: - PIN prompt (gated UI)

/// Sheet that asks for the existing PIN and unlocks the session on success.
struct ParentalPINPromptSheet: View {
    let title: String
    var message: String = String(localized: "Enter your parental controls PIN to continue.")
    var confirmLabel: String = String(localized: "Unlock")
    let onCancel: () -> Void
    /// Return `true` to dismiss (caller may also unlock session). Return `false` on wrong PIN.
    let onSuccess: (String) -> Bool

    @State private var pin = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .accessibilityHint(message)
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) {
                        submit()
                    }
                    .disabled(!ParentalControlsKeychain.isValidPIN(pin))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        if onSuccess(trimmed) {
            errorText = nil
        } else {
            errorText = String(localized: "Incorrect PIN")
            pin = ""
        }
    }
}

// MARK: - Set PIN (enable)

struct ParentalSetPINSheet: View {
    let title: String
    var confirmLabel: String = String(localized: "Save")
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var pin = ""
    @State private var confirm = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("PIN (4–6 digits)", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .accessibilityHint(String(localized: "Choose a 4–6 digit PIN. It is stored only in the Keychain."))
                    SecureField("Confirm PIN", text: $confirm)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .accessibilityHint(String(localized: "Confirm PIN"))
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.isStaticText)
                    }
                    Text("Choose a 4–6 digit PIN. It is stored only in the Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) {
                        save()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let a = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = confirm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ParentalControlsKeychain.isValidPIN(a) else {
            errorText = String(localized: "PIN must be 4–6 digits")
            return
        }
        guard a == b else {
            errorText = String(localized: "PINs don’t match")
            return
        }
        errorText = nil
        onSave(a)
    }
}

// MARK: - Change PIN

struct ParentalChangePINSheet: View {
    let onCancel: () -> Void
    let onSave: (String, String) throws -> Void

    @State private var current = ""
    @State private var newPIN = ""
    @State private var confirm = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current PIN", text: $current)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    SecureField("New PIN (4–6 digits)", text: $newPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .accessibilityHint(String(localized: "Choose a 4–6 digit PIN. It is stored only in the Keychain."))
                    SecureField("Confirm new PIN", text: $confirm)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = newPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = confirm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ParentalControlsKeychain.isValidPIN(a) else {
            errorText = String(localized: "New PIN must be 4–6 digits")
            return
        }
        guard a == b else {
            errorText = String(localized: "New PINs don’t match")
            return
        }
        do {
            try onSave(cur, a)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            current = ""
        }
    }
}
