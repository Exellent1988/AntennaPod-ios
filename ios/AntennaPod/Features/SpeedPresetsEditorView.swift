import PodcastCore
import SwiftUI

/// Settings → Playback → Speed presets (Android prefPlaybackSpeedArray, variable speed dialog
/// chips): add a speed, remove one (swipe or context menu), always sorted ascending, at least one.
struct SpeedPresetsEditorView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var newSpeed: Float = 1.75
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(settings.speedPresets, id: \.self) { speed in
                    HStack {
                        Text(PlaybackService.formatPlaybackSpeed(speed)).monospacedDigit()
                        if abs(speed - settings.defaultPlaybackSpeed) < 0.001 {
                            Text("Default").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { remove(speed) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .onDelete { offsets in
                    for i in offsets.sorted(by: >) where i < settings.speedPresets.count { remove(settings.speedPresets[i]) }
                }
            } header: {
                Text("Speed presets")
            } footer: {
                Text("Tap on the speed button in the player cycles through these presets; long-press lists them. Swipe to remove. At least one preset stays.")
            }
            Section("Add preset") {
                Stepper(value: $newSpeed, in: SpeedPresets.range, step: SpeedPresets.step) {
                    Text(PlaybackService.formatPlaybackSpeed(newSpeed)).monospacedDigit()
                }
                .accessibilityValue(PlaybackService.formatPlaybackSpeed(newSpeed))
                Button {
                    message = settings.addSpeedPreset(newSpeed) ? nil : String(localized: "This preset already exists.")
                } label: {
                    Label("Add", systemImage: "plus")
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Button("Reset to defaults (1.00×, 1.25×, 1.50×)", role: .destructive) {
                    settings.resetSpeedPresetsToAndroidDefault()
                    message = nil
                }
            }
        }
        .navigationTitle("Speed presets")
    }

    private func remove(_ speed: Float) {
        message = settings.removeSpeedPreset(speed) ? nil : String(localized: "At least one preset must remain.")
    }
}
