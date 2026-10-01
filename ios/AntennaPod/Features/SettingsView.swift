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
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var gpodder: GpodderSyncService
    @EnvironmentObject private var parental: ParentalControls

    @State private var customMB: Int = 500
    @State private var showClearConfirmation = false
    @State private var notificationAuthLabel = "Checking…"
    @State private var podcastIndexAPIKeyDraft = ""
    @State private var podcastIndexAPISecretDraft = ""
    @State private var podcastIndexKeysSaved = PodcastIndexKeychain.hasCredentials
    @State private var podcastIndexKeyError: String?
    @State private var showNetworkPINGate = false
    @State private var pendingNetworkUnlockAction: (() -> Void)?

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
                    Picker("Skip intro", selection: $settings.skipIntroSeconds) {
                        ForEach(AppSettings.skipIntroOutroPresets, id: \.self) { secs in
                            Text(AppSettings.skipIntroOutroLabel(secs)).tag(secs)
                        }
                    }
                    Picker("Skip outro", selection: $settings.skipOutroSeconds) {
                        ForEach(AppSettings.skipIntroOutroPresets, id: \.self) { secs in
                            Text(AppSettings.skipIntroOutroLabel(secs)).tag(secs)
                        }
                    }
                    Text("Skip intro seeks forward once on a fresh start (position near 0). Skip outro treats the episode as finished when remaining time is within the chosen window (mark played + continuous next). 0 = off. Global only; per-feed override later.")
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
                networkDownloadsSection
                notificationsSection
                storageSection
                podcastIndexDiscoverySection
                gpodderSyncSection
                Section("Library") {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.bar.doc.horizontal")
                    }
                }
                Section("Privacy") {
                    NavigationLink {
                        ParentalControlsSettingsView()
                    } label: {
                        Label("Parental controls", systemImage: "lock.shield")
                    }
                }
                Section("About") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
                DataBackupSection()
                OpmlImportExportSection()
            }
            .navigationTitle("Settings")
            .onAppear {
                if case .customMegabytes(let mb) = settings.downloadStorageLimit {
                    customMB = mb
                }
                downloads.runStorageMaintenance()
                Task { await refreshNotificationAuthLabel() }
                podcastIndexKeysSaved = PodcastIndexKeychain.hasCredentials
                if podcastIndexAPIKeyDraft.isEmpty {
                    podcastIndexAPIKeyDraft = PodcastIndexKeychain.loadAPIKey() ?? ""
                }
                // Secret is not pre-filled once saved (Keychain holds it); leave draft empty when already saved.
            }
            .onChange(of: settings.notifyOnNewEpisodes) { _, enabled in
                guard enabled else { return }
                Task {
                    await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
                    await refreshNotificationAuthLabel()
                }
            }
            .onChange(of: settings.notifyOnDownloadErrors) { _, enabled in
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
            return "When enabled, after a feed refresh the newest unplayed episodes (not already downloaded) are enqueued via DownloadService, capped per feed. Per-podcast Always/Never overrides are on each feed’s settings sheet. Storage-limit eviction still applies. Wi‑Fi-only for auto-download is under Network / Downloads."
        }
        return "After each feed refresh (Inbox pull-to-refresh, Keep updated, or a single podcast refresh), enqueues up to \(settings.autoDownloadEpisodesPerFeed.rawValue) newest unplayed episode(s) per feed. Override per podcast via Feed detail → gear. Always/Never beat this global toggle. Cellular gating is under Network / Downloads."
    }

    @ViewBuilder
    private var networkDownloadsSection: some View {
        Section {
            Toggle("Auto-download Wi‑Fi only", isOn: gatedWifiToggle(\AppSettings.autoDownloadWifiOnly))
            Toggle("Manual download Wi‑Fi only", isOn: gatedWifiToggle(\AppSettings.manualDownloadWifiOnly))
            Toggle("Stream Wi‑Fi only", isOn: gatedWifiToggle(\AppSettings.streamWifiOnly))
            if parental.isEnabled && parental.lockNetworkDownloadsSettings && parental.isLocked {
                Text("Network / Downloads settings are locked. Enter the parental PIN to change these toggles.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(networkDownloadsHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Network / Downloads")
        }
        .sheet(isPresented: $showNetworkPINGate) {
            ParentalPINPromptSheet(
                title: "Parental controls",
                message: "Enter your PIN to change Network / Downloads settings.",
                onCancel: {
                    showNetworkPINGate = false
                    pendingNetworkUnlockAction = nil
                },
                onSuccess: { pin in
                    if parental.unlockSession(with: pin) {
                        showNetworkPINGate = false
                        pendingNetworkUnlockAction?()
                        pendingNetworkUnlockAction = nil
                        return true
                    }
                    return false
                }
            )
        }
    }

    /// Binding that prompts for PIN when Network / Downloads settings are gated.
    private func gatedWifiToggle(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                if parental.needsPINForNetworkDownloads {
                    pendingNetworkUnlockAction = { settings[keyPath: keyPath] = newValue }
                    showNetworkPINGate = true
                } else {
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var networkDownloadsHelpText: String {
        "Uses NWPathMonitor (Wi‑Fi / Ethernet vs cellular). Auto-download Wi‑Fi only defaults on — skips enqueue on cellular. Manual download Wi‑Fi only (default off) refuses user downloads on cellular and records an error. Stream Wi‑Fi only (default off) blocks network stream URLs on cellular; local offline files still play. Turn a toggle off to allow cellular for that action."
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle("Notify on new episodes", isOn: $settings.notifyOnNewEpisodes)
            Toggle("Notify on download errors", isOn: $settings.notifyOnDownloadErrors)
            LabeledContent("Permission") {
                Text(notificationAuthLabel)
                    .foregroundStyle(.secondary)
            }
            if notificationAuthLabel == "Denied" {
                Button("Open iOS Settings") {
                    NewEpisodeNotificationCoordinator.openSystemNotificationSettings()
                }
            }
            NavigationLink {
                DownloadErrorsView()
            } label: {
                HStack {
                    Text("Download errors")
                    Spacer()
                    if !downloads.recentErrors.isEmpty {
                        Text("\(downloads.recentErrors.count)")
                            .foregroundStyle(.secondary)
                    }
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
        if notificationAuthLabel == "Denied" {
            return "Notification permission was denied. AntennaPod will not show banners until you allow Notifications in iOS Settings. Toggles stay on so your preference is clear. Sync-error notifications are not implemented yet."
        }
        if !settings.notifyOnNewEpisodes && !settings.notifyOnDownloadErrors {
            return "When enabled: new episodes after refresh, and/or download failures (episode title + short error). Local only — no push. Sync-error notifications later."
        }
        if notificationAuthLabel == "Not determined" {
            return "Permission is requested when you turn a notification toggle on, or when a refresh first finds new episodes / a download fails. Local only — no push."
        }
        var parts: [String] = []
        if settings.notifyOnNewEpisodes {
            parts.append("New episodes after refresh → Inbox")
        }
        if settings.notifyOnDownloadErrors {
            parts.append("Download failures → Downloads (title = episode, body = error)")
        }
        return parts.joined(separator: ". ") + ". No APNs / push. Sync-error notifications later."
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
            return "When an episode is marked played (manual or when playback finishes), its offline file is deleted via DownloadService. The episode row and played status stay. Skips while that local file is still the active player item, and skips favorited / starred episodes."
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

    @ViewBuilder
    private var podcastIndexDiscoverySection: some View {
        Section {
            Picker("Charts country", selection: chartsCountryBinding) {
                Text(automaticCountryLabel).tag("auto")
                ForEach(ChartsCountryPreference.pickerCodes, id: \.self) { code in
                    Text(countryPickerLabel(code)).tag(code)
                }
            }
            Text("Used by Home → Discover / Charts and Subscriptions → Discover. Apple iTunes RSS top podcasts (no API key). Automatic uses the device region, or de if unknown.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if podcastIndexKeysSaved {
                LabeledContent("API key") {
                    Text("Stored in Keychain")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("API secret") {
                    Text("Stored in Keychain")
                        .foregroundStyle(.secondary)
                }
                Button("Replace keys…") {
                    podcastIndexKeysSaved = false
                    podcastIndexAPIKeyDraft = ""
                    podcastIndexAPISecretDraft = ""
                    podcastIndexKeyError = nil
                }
                Button("Clear keys", role: .destructive) {
                    PodcastIndexKeychain.deleteCredentials()
                    podcastIndexKeysSaved = false
                    podcastIndexAPIKeyDraft = ""
                    podcastIndexAPISecretDraft = ""
                    podcastIndexKeyError = nil
                }
            } else {
                SecureField("API key", text: $podcastIndexAPIKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API secret", text: $podcastIndexAPISecretDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save keys") {
                    savePodcastIndexKeys()
                }
                .disabled(
                    podcastIndexAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || podcastIndexAPISecretDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            if let podcastIndexKeyError {
                Text(podcastIndexKeyError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(podcastIndexHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Discovery")
        }
    }

    private var chartsCountryBinding: Binding<String> {
        Binding(
            get: { settings.chartsCountryCode },
            set: { settings.chartsCountryCode = $0 }
        )
    }

    private var automaticCountryLabel: String {
        let resolved = ItunesTopListService.defaultCountryCode().uppercased()
        let name = Locale.current.localizedString(forRegionCode: resolved) ?? resolved
        return "Automatic (\(name) · \(resolved))"
    }

    private func countryPickerLabel(_ code: String) -> String {
        let upper = code.uppercased()
        let name = Locale.current.localizedString(forRegionCode: upper) ?? upper
        return "\(name) (\(upper))"
    }

    private var podcastIndexHelpText: String {
        "Free API key + secret from podcastindex.org (register / API docs). Stored only in the Keychain — not hardcoded and not shipped with the app. Used by Add podcast → Podcast Index search; Subscribe still follows the feed URL pipeline."
    }

    private func savePodcastIndexKeys() {
        let key = podcastIndexAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = podcastIndexAPISecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else {
            podcastIndexKeyError = "Enter both API key and secret"
            return
        }
        do {
            try PodcastIndexKeychain.save(apiKey: key, apiSecret: secret)
            podcastIndexAPISecretDraft = ""
            podcastIndexKeysSaved = true
            podcastIndexKeyError = nil
        } catch {
            podcastIndexKeyError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var gpodderSyncSection: some View {
        Section {
            Picker("Provider", selection: Binding(
                get: { gpodder.provider },
                set: { gpodder.selectProvider($0) }
            )) {
                ForEach(GpodderProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .disabled(gpodder.isBusy)

            if gpodder.provider == .nextcloud {
                TextField(
                    GpodderProvider.nextcloudPlaceholderHost,
                    text: $gpodder.host
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .disabled(gpodder.isLoggedIn)
            } else {
                TextField("Host", text: $gpodder.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(gpodder.isLoggedIn)
            }

            TextField("Username", text: $gpodder.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(gpodder.isLoggedIn)
            if !gpodder.isLoggedIn {
                SecureField("Password", text: $gpodder.passwordDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                LabeledContent("Password") {
                    Text("Stored in Keychain")
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Device name", text: $gpodder.deviceName)
                .disabled(gpodder.isBusy)
            LabeledContent("Device id") {
                Text(gpodder.deviceId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Button("Regenerate device id from name") {
                gpodder.regenerateDeviceIdFromName()
            }
            .disabled(gpodder.isBusy || gpodder.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if gpodder.isLoggedIn {
                Button {
                    Task { await gpodder.syncNow(store: store) }
                } label: {
                    if gpodder.isBusy {
                        Label("Working…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(gpodder.isBusy)
                Button("Logout", role: .destructive) {
                    gpodder.logout()
                }
                .disabled(gpodder.isBusy)
            } else {
                Button {
                    Task { await gpodder.login() }
                } label: {
                    if gpodder.isBusy {
                        Label("Logging in…", systemImage: "person.badge.key")
                    } else {
                        Label("Login", systemImage: "person.badge.key")
                    }
                }
                .disabled(gpodder.isBusy)
            }
            if let last = gpodder.lastSyncAt {
                LabeledContent("Last sync") {
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Last sync") {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            Text(gpodder.lastSyncStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let err = gpodder.lastSyncError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(gpodderHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Sync")
        }
    }

    private var gpodderHelpText: String {
        switch gpodder.provider {
        case .gpodderNet:
            return "Subscriptions only (beta MVP): Login stores the password in the Keychain; Sync pulls remote feed URLs and subscribes missing ones, then pushes local URLs not on the server. Merge is additive — remote removes do not unsubscribe local feeds. Episode actions (play/download) are not synced yet. Default host is https://gpodder.net (editable)."
        case .nextcloud:
            return "Nextcloud Gpodder Sync (beta MVP): same subscription limits as gpodder.net — additive pull/push of feed URLs; remote removes do not unsubscribe local feeds; episode actions not synced. Enter your Nextcloud base (server root or full API root like https://cloud.example.com/index.php/apps/gpoddersync/). Uses HTTP Basic (app password recommended). Requires the Gpodder Sync app on the server. Device id is kept for UI/state only (Nextcloud has no device API)."
        }
    }
}
