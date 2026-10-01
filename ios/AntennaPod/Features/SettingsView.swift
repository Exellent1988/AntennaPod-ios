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
    @State private var notificationAuthLabel = "Checking…"

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
                    Picker("Rewind", selection: $settings.rewindSeconds) {
                        ForEach(AppSettings.skipIntervalPresets, id: \.self) { secs in
                            Text("\(secs) seconds").tag(secs)
                        }
                    }
                    Picker("Fast-forward", selection: $settings.fastForwardSeconds) {
                        ForEach(AppSettings.skipIntervalPresets, id: \.self) { secs in
                            Text("\(secs) seconds").tag(secs)
                        }
                    }
                    Text("Used by mini player, full player, and Lockscreen / Now Playing skip buttons. Defaults match AntennaPod (10s back / 30s forward).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Playback source", selection: $settings.playbackSourcePreference) {
                        ForEach(PlaybackSourcePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    Text(settings.playbackSourcePreference.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                refreshSection
                autoDownloadSection
                notificationsSection
                storageSection
                OpmlImportExportSection()
            }
            .navigationTitle("Settings")
            .onAppear {
                if case .customMegabytes(let mb) = settings.downloadStorageLimit {
                    customMB = mb
                }
                downloads.runStorageMaintenance()
                Task { await refreshNotificationAuthLabel() }
            }
            .onChange(of: settings.notifyOnNewEpisodes) { _, enabled in
                guard enabled else { return }
                Task {
                    await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
                    await refreshNotificationAuthLabel()
                }
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
    private var refreshSection: some View {
        Section {
            Picker("Refresh interval", selection: $settings.refreshInterval) {
                ForEach(FeedRefreshInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            if let last = settings.lastFeedRefreshAt {
                LabeledContent("Last refresh") {
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Last refresh") {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            Text(refreshHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Feeds / Keep updated")
        }
    }

    private var refreshHelpText: String {
        if settings.refreshInterval == .manual {
            return "Feeds refresh only when you pull to refresh (Inbox) or refresh a podcast. Background App Refresh is not enabled in this beta (Info.plist has no fetch mode)."
        }
        return "When you open the app (launch or return to foreground), all subscriptions refresh if this interval has elapsed. Applies globally to every feed. Background App Refresh is stubbed until Info.plist adds fetch."
    }


    @ViewBuilder
    private var autoDownloadSection: some View {
        Section {
            Toggle("Auto-download", isOn: $settings.autoDownloadEnabled)
            if settings.autoDownloadEnabled {
                Picker("Episodes per feed", selection: $settings.autoDownloadEpisodesPerFeed) {
                    ForEach(AutoDownloadEpisodesPerFeed.allCases) { cap in
                        Text(cap.label).tag(cap)
                    }
                }
                Toggle("Wi‑Fi only", isOn: $settings.autoDownloadWifiOnly)
            }
            Text(autoDownloadHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Auto-download")
        }
    }

    private var autoDownloadHelpText: String {
        if !settings.autoDownloadEnabled {
            return "When enabled, after a feed refresh the newest unplayed episodes (not already downloaded) are enqueued via DownloadService, capped per feed. Per-podcast Always/Never overrides are on each feed’s settings sheet. Storage-limit eviction still applies."
        }
        let wifi = settings.autoDownloadWifiOnly
            ? " On cellular, auto-download is skipped (NWPathMonitor); manual downloads still work."
            : " Auto-download may use cellular."
        return "After each feed refresh (Inbox pull-to-refresh, Keep updated, or a single podcast refresh), enqueues up to \(settings.autoDownloadEpisodesPerFeed.rawValue) newest unplayed episode(s) per feed. Override per podcast via Feed detail → gear. Always/Never beat this global toggle.\(wifi)"
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle("Notify on new episodes", isOn: $settings.notifyOnNewEpisodes)
            LabeledContent("Permission") {
                Text(notificationAuthLabel)
                    .foregroundStyle(.secondary)
            }
            if notificationAuthLabel == "Denied" {
                Button("Open iOS Settings") {
                    NewEpisodeNotificationCoordinator.openSystemNotificationSettings()
                }
            }
            Text(notificationsHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Notifications")
        }
    }

    private var notificationsHelpText: String {
        if !settings.notifyOnNewEpisodes {
            return "When enabled, a local notification appears after a feed refresh that finds new episodes (title = podcast, body = episode title or “N new episodes”). No push server."
        }
        if notificationAuthLabel == "Denied" {
            return "Notification permission was denied. AntennaPod will not show banners until you allow Notifications in iOS Settings. The toggle stays on so your preference is clear."
        }
        if notificationAuthLabel == "Not determined" {
            return "Permission is requested when you turn this on, or when a refresh first finds new episodes. Local only — no push."
        }
        return "After Inbox pull-to-refresh, Keep updated, or a single podcast refresh, new episodes trigger a local notification. Tap opens Inbox (best-effort). No APNs / push."
    }

    @MainActor
    private func refreshNotificationAuthLabel() async {
        let status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationAuthLabel = "Allowed"
        case .denied:
            notificationAuthLabel = "Denied"
        case .notDetermined:
            notificationAuthLabel = "Not determined"
        @unknown default:
            notificationAuthLabel = "Unknown"
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            Toggle("Delete episode after playing", isOn: $settings.autoDeleteAfterPlaying)
            Text(autoDeleteHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var autoDeleteHelpText: String {
        if settings.autoDeleteAfterPlaying {
            return "When an episode is marked played (manual or when playback finishes), its offline file is deleted via DownloadService. The episode row and played status stay. Skips while that local file is still the active player item; favorites/starred are not implemented yet."
        }
        return "When enabled, offline files are removed after an episode is marked played. Episode metadata and played status are kept."
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
