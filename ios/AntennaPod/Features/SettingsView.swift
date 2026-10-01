import SwiftUI

/// Picker tags for the storage-limit section (maps to `DownloadStorageLimit`).
private enum StorageLimitPickerChoice: String, CaseIterable, Identifiable {
    case unlimited
    case gb1
    case gb5
    case gb10
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unlimited: return "Unlimited"
        case .gb1: return "1 GB"
        case .gb5: return "5 GB"
        case .gb10: return "10 GB"
        case .custom: return "Custom (MB)"
        }
    }

    static func from(_ limit: DownloadStorageLimit) -> StorageLimitPickerChoice {
        switch limit {
        case .unlimited: return .unlimited
        case .gigabytes(1): return .gb1
        case .gigabytes(5): return .gb5
        case .gigabytes(10): return .gb10
        case .gigabytes, .customMegabytes: return .custom
        }
    }

    func toLimit(customMB: Int) -> DownloadStorageLimit {
        switch self {
        case .unlimited: return .unlimited
        case .gb1: return .gigabytes(1)
        case .gb5: return .gigabytes(5)
        case .gb10: return .gigabytes(10)
        case .custom: return .customMegabytes(customMB)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService

    @State private var customMB: Int = 500
    @State private var showClearConfirmation = false

    private var pickerChoice: Binding<StorageLimitPickerChoice> {
        Binding(
            get: { StorageLimitPickerChoice.from(settings.downloadStorageLimit) },
            set: { choice in
                if case .customMegabytes(let mb) = settings.downloadStorageLimit {
                    customMB = mb
                }
                settings.downloadStorageLimit = choice.toLimit(customMB: customMB)
                downloads.runStorageMaintenance()
            }
        )
    }

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
                storageSection
                OpmlImportExportSection()
            }
            .navigationTitle("Settings")
            .onAppear {
                if case .customMegabytes(let mb) = settings.downloadStorageLimit {
                    customMB = mb
                }
                downloads.runStorageMaintenance()
            }
            .confirmationDialog(
                "Clear all downloads?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear downloads", role: .destructive) {
                    downloads.clearAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes \(downloads.downloads.count) offline episode file(s). Playback history is kept.")
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            LabeledContent("Used") {
                Text(storageUsedLabel)
                    .foregroundStyle(downloads.storageUsage.isOverLimit ? .red : .primary)
            }
            Picker("Max storage", selection: pickerChoice) {
                ForEach(StorageLimitPickerChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            if StorageLimitPickerChoice.from(settings.downloadStorageLimit) == .custom {
                Stepper(value: $customMB, in: AppSettings.customStorageMBRange, step: 50) {
                    Text("\(customMB) MB")
                }
                .onChange(of: customMB) { _, newValue in
                    settings.setCustomStorageLimitMegabytes(newValue)
                    downloads.runStorageMaintenance()
                }
            }
            Text(evictionHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear downloads", role: .destructive) {
                showClearConfirmation = true
            }
            .disabled(downloads.downloads.isEmpty)
        } header: {
            Text("Downloads / Storage")
        }
    }

    private var storageUsedLabel: String {
        let used = downloads.storageUsage.usedFormatted
        if let limit = downloads.storageUsage.limitFormatted {
            return "\(used) / \(limit)"
        }
        return "\(used) (unlimited)"
    }

    private var evictionHelpText: String {
        "When over the limit, played downloads are deleted first (oldest file first), then unplayed (LRU by file date). Runs after each successful download, when opening Settings, and on launch."
    }
}
