import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                }
                Section("Playback") {
                    Picker("Default speed", selection: $settings.defaultPlaybackSpeed) {
                        ForEach(AppSettings.speedPresets, id: \.self) { speed in
                            Text(String(format: "%.1f×", speed)).tag(speed)
                        }
                    }
                    Text("New episodes start at this speed. You can still change speed in the mini player.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
