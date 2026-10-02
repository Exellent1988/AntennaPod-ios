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

/// Settings tab: preferences Form with `.searchable` filter on section/row titles (+ footnotes where listed).
/// Empty sections hide while filtering; empty state when no matches. NavigationLinks stay live for visible rows.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var gpodder: GpodderSyncService
    @EnvironmentObject private var parental: ParentalControls

    @State private var customMB: Int = 500
    @State private var showClearConfirmation = false
    @State private var showCustomDefaultSpeed = false
    @State private var customSkipIntervalMode: CustomSkipIntervalSheet.Mode?
    @State private var showCustomSmartMark = false
    @Environment(\.scenePhase) private var scenePhase
    /// System notification auth — store status (not display string) so Denied checks survive EN/DE.
    @State private var notificationAuthStatus: NotificationAuthStatus = .checking
    @State private var podcastIndexAPIKeyDraft = ""
    @State private var podcastIndexAPISecretDraft = ""
    @State private var podcastIndexKeysSaved = PodcastIndexKeychain.hasCredentials
    @State private var podcastIndexKeyError: String?
    @State private var showNetworkPINGate = false
    @State private var pendingNetworkUnlockAction: (() -> Void)?
    @ObservedObject private var notificationDeepLink = NewEpisodeNotificationCoordinator.deepLink
    @ObservedObject private var networkPath = NetworkPathGate.shared
    @State private var ratingPromptUITick = 0
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var isSearchFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Case-insensitive match on source keys and their localized catalog values (EN/DE).
    private func matchesSearch(_ keys: String...) -> Bool {
        matchesSearch(Array(keys))
    }

    private func matchesSearch(_ keys: [String]) -> Bool {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return keys.contains { key in
            if key.localizedCaseInsensitiveContains(q) { return true }
            let localized = String(localized: String.LocalizationValue(key))
            return localized.localizedCaseInsensitiveContains(q)
        }
    }

    private func scheduleFilter(for term: String) {
        debounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            debouncedQuery = trimmed
        }
    }

    private var historySizeLimitBinding: Binding<HistorySizeLimit> {
        Binding(
            get: { settings.historySizeLimit },
            set: { newValue in
                settings.historySizeLimit = newValue
                store.trimHistoryToSizeLimitIfNeeded()
            }
        )
    }

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
            ScrollViewReader { proxy in
            Form {
                if matchesAppearanceSection {
                    appearanceSection
                }
                if matchesHomeSection {
                    homeSettingsSection
                }
                if matchesPlaybackSection {
                    playbackSettingsSection
                }
                if matchesQueueSection {
                    queueSettingsSection
                }
                if matchesSearch(
                    "Feeds / Keep updated",
                    "Refresh interval",
                    "Last refresh",
                    "Never",
                    "New episodes",
                    "Feeds refresh only when you pull to refresh (Inbox) or refresh a podcast. Background App Refresh is not enabled in this beta (Info.plist has no fetch mode).",
                    "When you open the app (launch or return to foreground), all subscriptions refresh if this interval has elapsed. Applies globally to every feed. Background App Refresh is stubbed until Info.plist adds fetch."
                ) {
                    refreshSection
                }
                if matchesSearch(
                    "Auto-download",
                    "Episodes per feed",
                    "When enabled, after a feed refresh only newly appeared episode IDs (not the whole backlog) are enqueued via DownloadService, capped per feed. Per-podcast Always/Never overrides are on each feed’s settings sheet. Local-folder feeds are skipped. Storage-limit eviction still applies. Runs on refresh success — no separate silent BGAppRefresh. Wi‑Fi-only for auto-download is under Network / Downloads."
                ) {
                    autoDownloadSection
                }
                if matchesSearch(
                    "Network / Downloads",
                    "Auto-download Wi‑Fi only",
                    "Manual download Wi‑Fi only",
                    "Stream Wi‑Fi only",
                    "Current network",
                    "Wi‑Fi",
                    "Cellular",
                    "mobile data",
                    "Mobilfunk",
                    "Ethernet",
                    "Offline",
                    "Network / Downloads settings are locked. Enter the parental PIN to change these toggles.",
                    "Wi‑Fi / Ethernet vs cellular (system path monitor — no VPN or proxy detection). Auto-download Wi‑Fi only defaults on — skips auto enqueue on cellular. Manual downloads allow cellular by default; Manual download Wi‑Fi only refuses user-initiated downloads on cellular and records an error. Stream Wi‑Fi only (default off) blocks network stream URLs on cellular; local offline files still play. Turn a toggle off to allow cellular for that action."
                ) {
                    networkDownloadsSection
                }
                if matchesSearch(
                    "Notifications",
                    "Notify on new episodes",
                    "Notify on download errors",
                    "Notify on sync errors",
                    "Notify when sleep timer ends",
                    "Permission",
                    "Open iOS Settings",
                    "Download errors",
                    "Allowed",
                    "Denied",
                    "Not determined",
                    "Notifies",
                    "Does not notify",
                    "local only",
                    "no push",
                    "APNs",
                    "download complete"
                ) {
                    notificationsSection
                }
                if matchesSearch(
                    "Downloads / Storage",
                    "Delete episode after playing",
                    "Used",
                    "Max storage",
                    "Max downloaded episodes",
                    "Parallel downloads",
                    "Clear downloads",
                    "Unlimited",
                    "Custom (MB)",
                    "25 episodes",
                    "50 episodes",
                    "100 episodes",
                    "200 episodes",
                    "500 episodes",
                    "1 at a time",
                    "2 parallel",
                    "3 parallel",
                    "4 parallel",
                    "5 parallel",
                    "When over the limit, played downloads are deleted first (oldest file first), then unplayed (LRU by file date). Runs after each successful download, when opening Settings, and on launch.",
                    "When over the episode count, played downloads that are not favorited and not queued are deleted first (oldest file first), then unplayed non-favorite non-queued (LRU). Favorites and queued episodes are never auto-deleted by this cap. Runs after each successful download, when opening Settings, and on launch. Separate from the Max storage byte budget.",
                    "Limits how many episode downloads run as active transfers at once (1–5, default 3). Extra downloads wait in memory until a slot frees. Waiting items are not persisted across process death; already-started background URLSession tasks continue after relaunch."
                ) {
                    storageSection
                }
                if matchesSearch(
                    "Discovery",
                    "Charts country",
                    "API key",
                    "API secret",
                    "Replace keys…",
                    "Clear keys",
                    "Save keys",
                    "Stored in Keychain",
                    "Free API key + secret from podcastindex.org (register / API docs). Stored only in the Keychain — not hardcoded and not shipped with the app. Used by Add podcast → Podcast Index search; Subscribe still follows the feed URL pipeline.",
                    "Used by Home → Discover / Charts and Subscriptions → Discover. Apple iTunes RSS top podcasts (no API key). Automatic uses the device region, or de if unknown."
                ) {
                    podcastIndexDiscoverySection
                }
                if matchesSearch(
                    "Sync",
                    "Provider",
                    "Host",
                    "Username",
                    "Password",
                    "Device name",
                    "Device id",
                    "Regenerate device id from name",
                    "Sync now",
                    "Login",
                    "Logout",
                    "Last sync",
                    "Working…",
                    "Logging in…",
                    "gpodder.net",
                    "Nextcloud",
                    "Synced",
                    "Local only",
                    "subscriptions",
                    "episode actions",
                    "bookmarks",
                    "tags",
                    "downloads",
                    "local folder",
                    "Keychain",
                    "additive"
                ) {
                    gpodderSyncSection
                        .id("settings-sync")
                }
                if matchesLibrarySection {
                    librarySettingsSection
                }
                if matchesSearch("Privacy", "Parental controls") {
                    Section("Privacy") {
                        NavigationLink {
                            ParentalControlsSettingsView()
                        } label: {
                            Label("Parental controls", systemImage: "lock.shield")
                        }
                    }
                }
                if matchesSearch(
                    "App Store",
                    "Ask for App Store rating",
                    "Mark-played count",
                    "Prompt attempted",
                    "Reset rating prompt state",
                    "Yes (once)",
                    "Not yet"
                ) {
                    appStoreRatingSection
                }
                if matchesSearch("Siri / Shortcuts", "Siri / Shortcuts (lite): Play/Pause, Skip forward, Skip back. Also open via URL schemes: antennapod://play, antennapod://pause, antennapod://toggle, antennapod://skip-forward, antennapod://skip-back. Intents open the app and control playback when an episode is already loaded. Not background-only without App Groups.") {
                    siriShortcutsSection
                }
                if matchesSearch("Homescreen widget", "Homescreen widget (beta lite): Continue listening shows episode title + podcast + remaining time (wall-clock max(0, duration − position) when duration known; ~ when unknown) from an App Group snapshot. Tap opens antennapod://play. Snapshot may be stale; no live scrubber. Add the widget from the iOS home screen after building with the AntennaPodWidget extension (App Group group.de.danoeh.antennapod.ios).") {
                    homescreenWidgetSection
                }
                if matchesSearch("Apple Watch", "Apple Watch (beta lite): Continue listening shows episode title + podcast + remaining time from the same snapshot as the homescreen widget (phone pushes via Watch Connectivity; App Group id group.de.danoeh.antennapod.ios). Play / Open on iPhone remotes antennapod://play on the companion. No independent Watch playback, downloads, or queue — when audio is already playing, use system Now Playing on the Watch. Requires AntennaPodWatch target, Dev Team, and App Group on Mac.") {
                    appleWatchSection
                }
                if matchesSearch("CarPlay", "CarPlay (honest partial): appears via system Now Playing when audio is playing — MPNowPlayingInfoCenter + remote play/pause/skip/seek (Settings intervals; next/previous → skip). Info.plist already has UIBackgroundModes audio; AVAudioSession category .playback. No custom CarPlay templates / CPTemplate scene / CarPlay entitlement. Apple Watch companion is a separate beta-lite target (Continue listening + Play on iPhone).") {
                    carPlaySection
                }
                if matchesSearch("About") {
                    Section("About") {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                    }
                }
                if matchesSearch(
                    "Backup",
                    "Export data backup",
                    "Import data backup",
                    "Include downloaded episode files"
                ) {
                    DataBackupSection()
                }
                if matchesSearch(
                    "Import / Export",
                    "Export OPML",
                    "Save OPML to Files…",
                    "Import OPML",
                    "Export subscriptions as HTML",
                    "Import from Files",
                    "Choose OPML file…"
                ) {
                    OpmlImportExportSection()
                }
                if isSearchFiltering && !hasAnyMatchingSettingsSection {
                    ContentUnavailableView(
                        "No matching settings",
                        systemImage: "magnifyingglass",
                        description: Text("No settings rows or sections match your search.")
                    )
                }
            }
            .navigationTitle("Settings")
            .searchable(text: $searchText, prompt: "Search settings")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onDisappear {
                debounceTask?.cancel()
            }
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
            .onChange(of: settings.notifyOnSyncErrors) { _, enabled in
                guard enabled else { return }
                Task {
                    await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
                    await refreshNotificationAuthLabel()
                }
            }
            .onChange(of: settings.notifyOnSleepTimerEnd) { _, enabled in
                guard enabled else { return }
                Task {
                    await NewEpisodeNotificationCoordinator.requestPermissionIfNeeded()
                    await refreshNotificationAuthLabel()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Re-read after returning from iOS Settings (Allow / Deny).
                guard phase == .active else { return }
                Task { await refreshNotificationAuthLabel() }
            }
            .onChange(of: notificationDeepLink.settingsSyncOpenToken) { _, token in
                guard token != nil else { return }
                // Defer slightly so the Settings tab is visible before scrolling.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation {
                        proxy.scrollTo("settings-sync", anchor: .top)
                    }
                }
            }
            } // ScrollViewReader
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
                Text(
                    "Deletes \(downloads.downloads.count) completed offline file(s) (\(DownloadStorageUsage.formatBytes(downloads.completedDownloadsByteSize()))), including favorited downloads. Uses the full Downloads catalog. Local files only — keeps played status, queue, favorites list, and history. Distinct from Delete played downloads and from Clear queue."
                )
            }
            .sheet(isPresented: $showCustomDefaultSpeed) {
                CustomPlaybackSpeedSheet(mode: .defaultSpeed, initialSpeed: settings.defaultPlaybackSpeed)
                    .environmentObject(playback)
                    .environmentObject(settings)
            }
            .sheet(item: $customSkipIntervalMode) { mode in
                CustomSkipIntervalSheet(
                    mode: mode,
                    initialSeconds: mode == .rewind ? settings.rewindSeconds : settings.fastForwardSeconds
                )
                .environmentObject(settings)
            }
            .sheet(isPresented: $showCustomSmartMark) {
                CustomSmartMarkSheet(initialSeconds: settings.smartMarkAsPlayedSeconds)
                    .environmentObject(settings)
            }
        }
    }

    private var hasAnyMatchingSettingsSection: Bool {
        matchesAppearanceSection
            || matchesHomeSection
            || matchesPlaybackSection
            || matchesQueueSection
            || matchesSearch(
                "Feeds / Keep updated",
                "Refresh interval",
                "Last refresh",
                "New episodes"
            )
            || matchesSearch("Auto-download", "Episodes per feed")
            || matchesSearch(
                "Network / Downloads",
                "Auto-download Wi‑Fi only",
                "Manual download Wi‑Fi only",
                "Stream Wi‑Fi only"
            )
            || matchesSearch(
                "Notifications",
                "Notify on new episodes",
                "Notify on download errors",
                "Notify on sync errors",
                "Notify when sleep timer ends",
                "Download errors"
            )
            || matchesSearch(
                "Downloads / Storage",
                "Delete episode after playing",
                "Max storage",
                "Parallel downloads",
                "Clear downloads"
            )
            || matchesSearch("Discovery", "Charts country", "API key", "API secret")
            || matchesSearch("Sync", "Provider", "Host", "Username", "Sync now", "Login", "Synced", "Local only", "Keychain", "bookmarks", "tags")
            || matchesLibrarySection
            || matchesSearch("Privacy", "Parental controls")
            || matchesSearch("App Store", "Ask for App Store rating", "Reset rating prompt state")
            || matchesSearch("Siri / Shortcuts")
            || matchesSearch("Homescreen widget")
            || matchesSearch("Apple Watch")
            || matchesSearch("CarPlay")
            || matchesSearch("About")
            || matchesSearch("Backup", "Export data backup", "Import data backup")
            || matchesSearch("Import / Export", "Export OPML", "Save OPML to Files…", "Import OPML", "Export subscriptions as HTML", "Import from Files", "Choose OPML file…")
    }

    private var matchesAppearanceSection: Bool {
        matchesSearch(
            "Appearance",
            "Theme",
            "Accent",
            "System follows the iOS appearance. Light and Dark force light or dark mode.",
            "Optional tint for buttons and highlights. System named SwiftUI colors only — no custom assets or Android themes. Default follows the app accent."
        )
    }

    private var matchesHomeSection: Bool {
        matchesSearch(
            "Home",
            "Home layout",
            "Configure Home",
            "reorder",
            "Downloads",
            "Show, hide, and drag-reorder Home tab sections (Continue, Inbox, Queue, Discover, Recently updated, Favorites). Search filters section labels; Edit/drag reorder is off while searching. Reset restores the full default layout after confirmation. Empty optional sections still hide when they have no items. Favorites is off by default. No Downloads Home section — use the Downloads tab. Same editor as Home toolbar Configure Home."
        )
    }

    private var matchesQueueSection: Bool {
        matchesSearch(
            "Queue",
            "Lock queue",
            "When on, the Queue tab disables Edit drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Move playing to top, and hides EpisodeRow Move to top / Move to bottom. Enqueue, Play Next, Remove, Archive swipe, and Clear queue stay available (reorder lock only — same idea as AntennaPod Android queue lock). Same preference as the Queue toolbar lock button. Default off."
        )
    }

    private var matchesLibrarySection: Bool {
        matchesSearch(
            "Library",
            "Manage tags",
            "Statistics",
            "Echo",
            "History size",
            "50 episodes",
            "100 episodes",
            "200 episodes",
            "500 episodes",
            "Unlimited",
            "Caps History-listed episodes in playback.json (played / in-progress). Oldest by lastPlayedAt (else updatedAt) are removed first — same as Remove from history (progress and played flags gone). Unlimited keeps the full list. Does not touch favorites, archive, downloads, or queue. Statistics and Continue listening may lose trimmed episodes. Default Unlimited."
        )
    }

    /// Row-level keywords for Playback (section shows if header or any row matches).
    private var matchesPlaybackSection: Bool {
        matchesSearch("Playback")
            || matchesPlaybackSpeed
            || matchesPlaybackSkipButtons
            || matchesPlaybackIntroOutro
            || matchesPlaybackSource
            || matchesPlaybackVideoAudio
            || matchesPlaybackVolume
            || matchesPlaybackSkipSilence
            || matchesPlaybackStereo
            || matchesPlaybackPreservePitch
            || matchesPlaybackKeepScreen
            || matchesPlaybackContinuous
            || matchesPlaybackResetPosition
            || matchesPlaybackRemaining
            || matchesPlaybackRewindPause
            || matchesPlaybackSmartMark
    }

    private var matchesPlaybackSpeed: Bool {
        matchesSearch(
            "Default speed",
            "Custom…",
            "Custom default speed",
            "New episodes start at this speed. In the mini/full player, tap cycles presets; long-press opens the full list and Custom…. Custom… also available in Settings (0.50×–3.00×)."
        )
    }

    private var matchesPlaybackSkipButtons: Bool {
        matchesSearch(
            "Rewind",
            "Fast-forward",
            "Custom…",
            "Custom rewind",
            "Custom fast-forward",
            "Used by mini player, full player, and Lockscreen / Now Playing skip buttons. Defaults match AntennaPod (10s back / 30s forward). Presets 5/10/15/20/30/60 plus Custom… (5–60 seconds)."
        )
    }

    private var matchesPlaybackIntroOutro: Bool {
        matchesSearch(
            "Skip intro",
            "Skip outro",
            "Skip intro seeks forward once on a fresh start (position near 0). Skip outro treats the episode as finished when remaining time is within the chosen window (mark played + continuous next). 0 = off. Override per podcast via Feed detail → gear → Playback."
        )
    }

    private var matchesPlaybackSource: Bool {
        matchesSearch("Playback source")
    }

    private var matchesPlaybackVideoAudio: Bool {
        matchesSearch(
            "Play video as audio only",
            "When on, video episodes (MIME video/* or mp4/m4v/mov/webm) show artwork in the full player instead of a video surface. Lockscreen / Now Playing stays audio either way. Picture-in-picture is not included in this beta. Default off."
        )
    }

    private var matchesPlaybackVolume: Bool {
        matchesSearch(
            "Volume adaptation",
            "Optimize for speech via the iOS `AVAudioSession` mode (`.spokenAudio`, or `.voiceChat` fallback). When off, audio uses `.default` and video (surface shown) uses `.moviePlayback`. This is a **session mode**, not Android's LoudnessEnhancer gain curve. Default off."
        )
    }

    private var matchesPlaybackSkipSilence: Bool {
        matchesSearch(
            "Skip silence",
            "Preference only — **not applied** on stock `AVPlayer`. Android skip-silence needs a custom `AVAudioEngine` / player-node graph; wiring that would break the shared video surface, Now Playing, and rate path. Enabling this toggle has no playback effect in this beta. Default off."
        )
    }

    private var matchesPlaybackStereo: Bool {
        matchesSearch(
            "Stereo to mono",
            "When on, requests mono output via `AVAudioSession.setPreferredOutputNumberOfChannels(1)` (restores up to 2 when off). **Best-effort** — the system may ignore this depending on the route (built-in speaker, Bluetooth, CarPlay, etc.). Keeps stock `AVPlayer` (video surface, PiP, Now Playing). Not Android ExoPlayer stereo→mono remix. Default off."
        )
    }

    private var matchesPlaybackPreservePitch: Bool {
        matchesSearch(
            "Preserve pitch",
            "When on (default), keeps natural pitch while changing playback speed via `AVPlayerItem.audioTimePitchAlgorithm` `.timeDomain` (speech-oriented). When off, pitch scales with rate (`.varispeed` — chipmunk / slow voice). Stock `AVPlayer` only — not Android ExoPlayer / Sonic. Not Skip Silence."
        )
    }

    private var matchesPlaybackKeepScreen: Bool {
        matchesSearch(
            "Keep screen on",
            "When on, disables the idle timer while playback is actively playing so the screen stays awake. Restored when paused, stopped, or no episode. Default off (battery-friendly). Does not override Low Power Mode beyond the idle timer; no brightness changes; Picture in Picture and background audio are unchanged."
        )
    }

    private var matchesPlaybackContinuous: Bool {
        matchesSearch(
            "Continuous playback",
            "When on, finishing an episode auto-plays the next item from the Queue only (not the next episode of the same podcast). When off, episode end still marks played / saves progress but does not advance. End-of-episode sleep timer always stops without advancing. Default on."
        )
    }

    private var matchesPlaybackResetPosition: Bool {
        matchesSearch(
            "Reset position when marked played",
            "When on, marking an episode played clears its saved playback position to 0 (resume from start later). When off, the position is kept so Mark unplayed can resume. Applies to manual mark, mark-all, smart mark, and natural end. Default on."
        )
    }

    private var matchesPlaybackRemaining: Bool {
        matchesSearch(
            "Show remaining time",
            "When on, the mini and full player show remaining time (−m:ss) on the right instead of total duration. Left stays current position. Tap the full-player duration/remaining label to toggle. Default off."
        )
    }

    private var matchesPlaybackRewindPause: Bool {
        matchesSearch(
            "Rewind after pause",
            "When resuming after a pause of at least 1 second, seek backward by this many seconds so you do not lose context. Off (0) disables. Does not apply on first start / cold play from a row — only after an actual pause of the current item. Fixed amount (honest beta; not Android’s elapsed-time tiers). Default 2."
        )
    }

    private var matchesPlaybackSmartMark: Bool {
        matchesSearch(
            "Smart mark as played",
            "Custom…",
            "Custom smart mark",
            "Mark as played when leaving or stopping within this many seconds of the end (AntennaPod smart mark). Presets Off/15/30/60/120/300/600 plus Custom… (1–600 seconds). Off (0) = only on natural end or explicit mark — not near-end scrub. Default 30. Seconds remaining only — not a percent threshold."
        )
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            if matchesSearch(
                "Appearance",
                "Theme",
                "System follows the iOS appearance. Light and Dark force light or dark mode."
            ) {
                Picker(String(localized: "Theme"), selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .accessibilityLabel(String(localized: "Theme"))
                .accessibilityValue(settings.theme.label)
                .accessibilityHint(String(localized: "System follows the iOS appearance. Light and Dark force light or dark mode."))
                Text(String(localized: "System follows the iOS appearance. Light and Dark force light or dark mode."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "System follows the iOS appearance. Light and Dark force light or dark mode."))
            }
            if matchesSearch(
                "Appearance",
                "Accent",
                "Optional tint for buttons and highlights. System named SwiftUI colors only — no custom assets or Android themes. Default follows the app accent."
            ) {
                Picker(String(localized: "Accent"), selection: $settings.accentColor) {
                    ForEach(AppAccentColor.allCases) { accent in
                        Text(accent.label).tag(accent)
                    }
                }
                .accessibilityLabel(String(localized: "Accent"))
                .accessibilityValue(settings.accentColor.label)
                .accessibilityHint(String(localized: "Optional tint for buttons and highlights. System named SwiftUI colors only — no custom assets or Android themes. Default follows the app accent."))
                Text(String(localized: "Optional tint for buttons and highlights. System named SwiftUI colors only — no custom assets or Android themes. Default follows the app accent."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Optional tint for buttons and highlights. System named SwiftUI colors only — no custom assets or Android themes. Default follows the app accent."))
            }
        }
    }

    @ViewBuilder
    private var homeSettingsSection: some View {
        Section("Home") {
            NavigationLink {
                HomeLayoutSettingsView()
            } label: {
                Label("Home layout", systemImage: "rectangle.grid.1x2")
            }
            .accessibilityHint(
                String(localized: "Show, hide, and drag-reorder Home tab sections. Same editor as Home toolbar Configure Home. Persisted in AppSettings / backup. No Downloads Home section.")
            )
            Text(String(localized: "Show, hide, and drag-reorder Home tab sections (Continue, Inbox, Queue, Discover, Recently updated, Favorites). Search filters section labels; Edit/drag reorder is off while searching. Reset restores the full default layout after confirmation. Empty optional sections still hide when they have no items. Favorites is off by default. No Downloads Home section — use the Downloads tab. Same editor as Home toolbar Configure Home."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Home layout help"))
                .accessibilityValue(String(localized: "Show, hide, and drag-reorder Home tab sections (Continue, Inbox, Queue, Discover, Recently updated, Favorites). Search filters section labels; Edit/drag reorder is off while searching. Reset restores the full default layout after confirmation. Empty optional sections still hide when they have no items. Favorites is off by default. No Downloads Home section — use the Downloads tab. Same editor as Home toolbar Configure Home."))
        }
    }

    @ViewBuilder
    private var queueSettingsSection: some View {
        Section("Queue") {
            Toggle("Lock queue", isOn: $settings.queueLocked)
                .accessibilityHint(String(localized: "When on, disables Queue drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Move playing to top, and Move to top or bottom. Enqueue, Play Next, Remove, and Clear queue still work. Default off."))
            Text("When on, the Queue tab disables Edit drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Move playing to top, and hides EpisodeRow Move to top / Move to bottom. Enqueue, Play Next, Remove, Archive swipe, and Clear queue stay available (reorder lock only — same idea as AntennaPod Android queue lock). Same preference as the Queue toolbar lock button. Default off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var librarySettingsSection: some View {
        Section("Library") {
            if matchesSearch("Library", "Manage tags") {
                NavigationLink {
                    ManageTagsView()
                } label: {
                    Label("Manage tags", systemImage: "tag")
                }
                .accessibilityHint(String(localized: "Rename or delete subscription tags across all podcasts"))
            }
            if matchesSearch(
                "Library",
                "History size",
                "50 episodes",
                "100 episodes",
                "200 episodes",
                "500 episodes",
                "Unlimited",
                "Caps History-listed episodes in playback.json (played / in-progress). Oldest by lastPlayedAt (else updatedAt) are removed first — same as Remove from history (progress and played flags gone). Unlimited keeps the full list. Does not touch favorites, archive, downloads, or queue. Statistics and Continue listening may lose trimmed episodes. Default Unlimited."
            ) {
                Picker("History size", selection: historySizeLimitBinding) {
                    ForEach(HistorySizeLimit.allCases) { limit in
                        Text(limit.label).tag(limit)
                    }
                }
                .accessibilityLabel(String(localized: "History size"))
                .accessibilityValue(settings.historySizeLimit.label)
                .accessibilityHint(String(localized: "Maximum episodes kept in History. Oldest last-played entries are removed first."))
                Text("Caps History-listed episodes in playback.json (played / in-progress). Oldest by lastPlayedAt (else updatedAt) are removed first — same as Remove from history (progress and played flags gone). Unlimited keeps the full list. Does not touch favorites, archive, downloads, or queue. Statistics and Continue listening may lose trimmed episodes. Default Unlimited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesSearch("Library", "Statistics") {
                NavigationLink {
                    StatisticsView()
                } label: {
                    Label("Statistics", systemImage: "chart.bar.doc.horizontal")
                }
            }
            if matchesSearch("Library", "Echo") {
                NavigationLink {
                    EchoView()
                } label: {
                    Label("Echo", systemImage: "sparkles.rectangle.stack")
                }
            }
        }
    }

    @ViewBuilder
    private var playbackSettingsSection: some View {
        Section("Playback") {
            if matchesPlaybackSpeed {
                Picker("Default speed", selection: $settings.defaultPlaybackSpeed) {
                    ForEach(AppSettings.speedPresets, id: \.self) { speed in
                        Text(PlaybackService.formatPlaybackSpeed(speed)).tag(speed)
                    }
                    if !AppSettings.speedPresets.contains(settings.defaultPlaybackSpeed) {
                        Text(PlaybackService.formatPlaybackSpeed(settings.defaultPlaybackSpeed))
                            .tag(settings.defaultPlaybackSpeed)
                    }
                }
                Button(String(localized: "Custom…")) {
                    showCustomDefaultSpeed = true
                }
                .accessibilityHint(String(localized: "Set a custom default playback speed between 0.50× and 3.00×."))
                Text(String(localized: "New episodes start at this speed. In the mini/full player, tap cycles presets; long-press opens the full list and Custom…. Custom… also available in Settings (0.50×–3.00×)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackSkipButtons {
                Picker("Rewind", selection: $settings.rewindSeconds) {
                    ForEach(AppSettings.skipIntervalPresets, id: \.self) { secs in
                        Text(AppSettings.skipIntervalLabel(secs)).tag(secs)
                    }
                    if !AppSettings.skipIntervalPresets.contains(settings.rewindSeconds) {
                        Text(AppSettings.skipIntervalLabel(settings.rewindSeconds))
                            .tag(settings.rewindSeconds)
                    }
                }
                Button(String(localized: "Custom…")) {
                    customSkipIntervalMode = .rewind
                }
                .accessibilityHint(String(localized: "Set a custom rewind interval between 5 and 60 seconds."))
                Picker("Fast-forward", selection: $settings.fastForwardSeconds) {
                    ForEach(AppSettings.skipIntervalPresets, id: \.self) { secs in
                        Text(AppSettings.skipIntervalLabel(secs)).tag(secs)
                    }
                    if !AppSettings.skipIntervalPresets.contains(settings.fastForwardSeconds) {
                        Text(AppSettings.skipIntervalLabel(settings.fastForwardSeconds))
                            .tag(settings.fastForwardSeconds)
                    }
                }
                Button(String(localized: "Custom…")) {
                    customSkipIntervalMode = .fastForward
                }
                .accessibilityHint(String(localized: "Set a custom fast-forward interval between 5 and 60 seconds."))
                Text(String(localized: "Used by mini player, full player, and Lockscreen / Now Playing skip buttons. Defaults match AntennaPod (10s back / 30s forward). Presets 5/10/15/20/30/60 plus Custom… (5–60 seconds)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackIntroOutro {
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
                Text("Skip intro seeks forward once on a fresh start (position near 0). Skip outro treats the episode as finished when remaining time is within the chosen window (mark played + continuous next). 0 = off. Override per podcast via Feed detail → gear → Playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackSource {
                Picker("Playback source", selection: $settings.playbackSourcePreference) {
                    ForEach(PlaybackSourcePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                Text(settings.playbackSourcePreference.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackVideoAudio {
                Toggle("Play video as audio only", isOn: $settings.playVideoAsAudioOnly)
                    .accessibilityHint(String(localized: "Hides the video surface and shows artwork instead. Lockscreen stays audio."))
                Text("When on, video episodes (MIME video/* or mp4/m4v/mov/webm) show artwork in the full player instead of a video surface. Lockscreen / Now Playing stays audio either way. Picture-in-picture is not included in this beta. Default off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackVolume {
                Toggle("Volume adaptation", isOn: $settings.volumeAdaptationEnabled)
                    .accessibilityHint(String(localized: "Optimizes the audio session for speech. Not Android loudness gain."))
                Text("Optimize for speech via the iOS `AVAudioSession` mode (`.spokenAudio`, or `.voiceChat` fallback). When off, audio uses `.default` and video (surface shown) uses `.moviePlayback`. This is a **session mode**, not Android's LoudnessEnhancer gain curve. Default off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackSkipSilence {
                Toggle("Skip silence", isOn: $settings.skipSilenceEnabled)
                    .accessibilityHint(String(localized: "Preference only; not applied on stock AVPlayer in this beta."))
                Text("Preference only — **not applied** on stock `AVPlayer`. Android skip-silence needs a custom `AVAudioEngine` / player-node graph; wiring that would break the shared video surface, Now Playing, and rate path. Enabling this toggle has no playback effect in this beta. Default off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackStereo {
                Toggle("Stereo to mono", isOn: $settings.stereoToMonoEnabled)
                    .accessibilityHint(String(localized: "Best-effort mono via AVAudioSession preferred channels. Route-dependent; not AVAudioMix remix. Default off."))
                Text("When on, requests mono output via `AVAudioSession.setPreferredOutputNumberOfChannels(1)` (restores up to 2 when off). Reapplied on play, Settings change, and audio route change. **Best-effort** — the system may ignore this depending on the route (built-in speaker, Bluetooth, CarPlay, etc.). `AVMutableAudioMix` only scales track volume (no L+R→mono); a real remix needs `MTAudioProcessingTap` (file-based only, not HLS) or `AVAudioEngine` (would break video / PiP / Now Playing). Keeps stock `AVPlayer`. Not Android ExoPlayer stereo→mono remix. Default off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackPreservePitch {
                Toggle("Preserve pitch", isOn: $settings.preservePitchEnabled)
                    .accessibilityHint(String(localized: "Keeps natural pitch when changing playback speed. Off → chipmunk / slow voice. Default on."))
                Text("When on (default), keeps natural pitch while changing playback speed via `AVPlayerItem.audioTimePitchAlgorithm` `.timeDomain` (speech-oriented). When off, pitch scales with rate (`.varispeed` — chipmunk / slow voice). Stock `AVPlayer` only — not Android ExoPlayer / Sonic. Not Skip Silence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackKeepScreen {
                Toggle("Keep screen on", isOn: $settings.keepScreenOnWhilePlaying)
                    .accessibilityHint(String(localized: "Prevents idle lock while audio or video is actively playing. Default off."))
                Text("When on, disables the idle timer while playback is actively playing so the screen stays awake. Restored when paused, stopped, or no episode. Default off (battery-friendly). Does not override Low Power Mode beyond the idle timer; no brightness changes; Picture in Picture and background audio are unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackContinuous {
                Toggle("Continuous playback", isOn: $settings.continuousPlaybackEnabled)
                    .accessibilityHint(String(localized: "When on, finishing an episode auto-plays the next Queue item only — not the next episode of the same podcast. Default on."))
                Text("When on, finishing an episode auto-plays the next item from the Queue only (not the next episode of the same podcast). When off, episode end still marks played / saves progress but does not advance. End-of-episode sleep timer always stops without advancing. Default on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackResetPosition {
                Toggle("Reset position when marked played", isOn: $settings.resetPositionWhenMarkedPlayed)
                    .accessibilityHint(String(localized: "When on, mark played clears saved position to 0. When off, keeps position for resume after Mark unplayed. Default on."))
                Text("When on, marking an episode played clears its saved playback position to 0 (resume from start later). When off, the position is kept so Mark unplayed can resume. Applies to manual mark, mark-all, smart mark, and natural end. Default on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackRemaining {
                Toggle("Show remaining time", isOn: $settings.showRemainingTime)
                    .accessibilityHint(String(localized: "When on, player time labels show time left instead of total duration. Default off."))
                Text("When on, the mini and full player show remaining time (−m:ss) on the right instead of total duration. Left stays current position. Tap the full-player duration/remaining label to toggle. Default off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackRewindPause {
                Picker("Rewind after pause", selection: $settings.rewindAfterPauseSeconds) {
                    ForEach(AppSettings.rewindAfterPausePresets, id: \.self) { secs in
                        Text(AppSettings.rewindAfterPauseLabel(secs)).tag(secs)
                    }
                }
                .accessibilityHint(String(localized: "Seconds to seek back when resuming after a pause of at least 1 second. Off disables. Default 2."))
                Text("When resuming after a pause of at least 1 second, seek backward by this many seconds so you do not lose context. Off (0) disables. Does not apply on first start / cold play from a row — only after an actual pause of the current item. Fixed amount (honest beta; not Android’s elapsed-time tiers). Default 2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackSmartMark {
                Picker("Smart mark as played", selection: $settings.smartMarkAsPlayedSeconds) {
                    ForEach(AppSettings.smartMarkAsPlayedPresets, id: \.self) { secs in
                        Text(AppSettings.smartMarkAsPlayedLabel(secs)).tag(secs)
                    }
                    if !AppSettings.smartMarkAsPlayedPresets.contains(settings.smartMarkAsPlayedSeconds) {
                        Text(AppSettings.smartMarkAsPlayedLabel(settings.smartMarkAsPlayedSeconds))
                            .tag(settings.smartMarkAsPlayedSeconds)
                    }
                }
                .accessibilityHint(String(localized: "Seconds before end that count as played when leaving. Off marks only on natural end. Presets plus Custom… 1–600. Default 30."))
                Button(String(localized: "Custom…")) {
                    showCustomSmartMark = true
                }
                .accessibilityHint(String(localized: "Set a custom smart mark threshold between 1 and 600 seconds remaining."))
                Text(String(localized: "Mark as played when leaving or stopping within this many seconds of the end (AntennaPod smart mark). Presets Off/15/30/60/120/300/600 plus Custom… (1–600 seconds). Off (0) = only on natural end or explicit mark — not near-end scrub. Default 30. Seconds remaining only — not a percent threshold."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Picker("New episodes", selection: $settings.newEpisodeAction) {
                ForEach(NewEpisodeAction.allCases) { action in
                    Text(action.label).tag(action)
                }
            }
            Text(settings.newEpisodeAction.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Feeds / Keep updated")
        }
    }

    private var refreshHelpText: String {
        if settings.refreshInterval == .manual {
            return String(localized: "Feeds refresh only when you pull to refresh (Inbox) or refresh a podcast. Background App Refresh is not enabled in this beta (Info.plist has no fetch mode).")
        }
        return String(localized: "When you open the app (launch or return to foreground), all subscriptions refresh if this interval has elapsed. Applies globally to every feed. Background App Refresh is stubbed until Info.plist adds fetch.")
    }


    @ViewBuilder
    private var autoDownloadSection: some View {
        Section {
            Toggle("Auto-download", isOn: $settings.autoDownloadEnabled)
                .accessibilityHint(String(localized: "Downloads newly appeared unplayed episodes after a feed refresh when enabled."))
            if settings.autoDownloadEnabled {
                Picker(String(localized: "Episodes per feed"), selection: $settings.autoDownloadEpisodesPerFeed) {
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
            return String(localized: "When enabled, after a feed refresh only newly appeared episode IDs (not the whole backlog) are enqueued via DownloadService, capped per feed. Per-podcast Always/Never overrides are on each feed’s settings sheet. Local-folder feeds are skipped. Storage-limit eviction still applies. Runs on refresh success — no separate silent BGAppRefresh. Wi‑Fi-only for auto-download is under Network / Downloads.")
        }
        return String(localized: "After each feed refresh (Inbox pull-to-refresh, Keep updated, or a single podcast refresh), enqueues up to \(settings.autoDownloadEpisodesPerFeed.rawValue) newly appeared unplayed episode(s) per feed (not backlog). Override per podcast via Feed detail → gear. Always/Never beat this global toggle. Local-folder / file:// feeds skipped. Cellular gating is under Network / Downloads.")
    }

    @ViewBuilder
    private var networkDownloadsSection: some View {
        Section {
            LabeledContent(String(localized: "Current network")) {
                Text(networkPath.kind.statusLabel)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(networkPath.kind.accessibilityLabel)
            .accessibilityHint(String(localized: "Live status from the system path monitor. Wi‑Fi and Ethernet allow Wi‑Fi-only actions; cellular does not. No VPN or proxy detection."))

            Toggle(String(localized: "Auto-download Wi‑Fi only"), isOn: gatedWifiToggle(\AppSettings.autoDownloadWifiOnly))
                .accessibilityLabel(String(localized: "Auto-download Wi‑Fi only"))
                .accessibilityHint(String(localized: "When on (default), auto-download after refresh skips cellular. Does not block manual downloads."))
            Toggle(String(localized: "Manual download Wi‑Fi only"), isOn: gatedWifiToggle(\AppSettings.manualDownloadWifiOnly))
                .accessibilityLabel(String(localized: "Manual download Wi‑Fi only"))
                .accessibilityHint(String(localized: "When on, user-initiated downloads are refused on cellular and an error is recorded. Default off — manual downloads may use mobile data."))
            Toggle(String(localized: "Stream Wi‑Fi only"), isOn: gatedWifiToggle(\AppSettings.streamWifiOnly))
                .accessibilityLabel(String(localized: "Stream Wi‑Fi only"))
                .accessibilityHint(String(localized: "When on, network streaming is blocked on cellular; local offline files still play. Default off."))
            if parental.isEnabled && parental.lockNetworkDownloadsSettings && parental.isLocked {
                Text(String(localized: "Network / Downloads settings are locked. Enter the parental PIN to change these toggles."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(networkDownloadsHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(networkDownloadsHelpText)
        } header: {
            Text(String(localized: "Network / Downloads"))
        }
        .onAppear {
            AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
        }
        .sheet(isPresented: $showNetworkPINGate) {
            ParentalPINPromptSheet(
                title: "Parental controls",
                message: String(localized: "Enter your PIN to change Network / Downloads settings."),
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
        String(localized: "Wi‑Fi / Ethernet vs cellular (system path monitor — no VPN or proxy detection). Auto-download Wi‑Fi only defaults on — skips auto enqueue on cellular. Manual downloads allow cellular by default; Manual download Wi‑Fi only refuses user-initiated downloads on cellular and records an error. Stream Wi‑Fi only (default off) blocks network stream URLs on cellular; local offline files still play. Turn a toggle off to allow cellular for that action.")
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle("Notify on new episodes", isOn: $settings.notifyOnNewEpisodes)
                .accessibilityHint(String(localized: "Local notifications only after a feed refresh finds new episodes; no push server."))
            Toggle("Notify on download errors", isOn: $settings.notifyOnDownloadErrors)
                .accessibilityHint(String(localized: "Local notifications when a download fails — not when a download completes successfully."))
            Toggle("Notify on sync errors", isOn: $settings.notifyOnSyncErrors)
                .accessibilityHint(String(localized: "Local notifications when gpodder or Nextcloud sync fails."))
            Toggle("Notify when sleep timer ends", isOn: $settings.notifyOnSleepTimerEnd)
                .accessibilityHint(String(localized: "Local notification and haptic when the sleep timer pauses or stops playback."))

            LabeledContent("Permission") {
                Text(notificationAuthStatus.label)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Permission"))
            .accessibilityValue(notificationAuthStatus.label)

            if notificationAuthStatus == .denied {
                Button("Open iOS Settings") {
                    NewEpisodeNotificationCoordinator.openSystemNotificationSettings()
                }
                .accessibilityHint(String(localized: "Opens the system Settings app so you can allow Notifications for AntennaPod. App toggles stay on; banners stay off until iOS allows them."))
            }

            LabeledContent("Notifies") {
                Text(String(localized: "New episodes after refresh (one local banner → Inbox); download failures → Downloads; sync/login failures → Settings Sync; sleep timer end (banner + foreground haptic)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Notifies"))
            .accessibilityValue(String(localized: "New episodes after refresh (one local banner → Inbox); download failures → Downloads; sync/login failures → Settings Sync; sleep timer end (banner + foreground haptic)"))

            LabeledContent("Does not notify") {
                Text(String(localized: "No push / APNs / server-side alerts. No download-complete success banners. No episode-level deep link for new episodes (Inbox only). Needs an in-app refresh, download, sync, or sleep-timer fire — not a remote push."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Does not notify"))
            .accessibilityValue(String(localized: "No push / APNs / server-side alerts. No download-complete success banners. No episode-level deep link for new episodes (Inbox only). Needs an in-app refresh, download, sync, or sleep-timer fire — not a remote push."))

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
                .accessibilityLabel(String(localized: "Notifications help"))
                .accessibilityValue(notificationsHelpText)
        } header: {
            Text("Notifications")
        }
    }

    private var notificationsHelpText: String {
        if notificationAuthStatus == .denied {
            return String(localized: "Notification permission was denied. AntennaPod will not show banners until you allow Notifications in iOS Settings (Open iOS Settings). Toggles stay on so your preference is clear. Local UserNotifications only — never push / APNs / server-side alerts. No download-complete banners.")
        }
        if !settings.notifyOnNewEpisodes && !settings.notifyOnDownloadErrors && !settings.notifyOnSyncErrors && !settings.notifyOnSleepTimerEnd {
            return String(localized: "When enabled: new episodes after refresh (one aggregated local banner → Inbox), download failures → Downloads, gpodder/Nextcloud login or sync failures → Settings Sync, and/or sleep timer end (banner + foreground haptic). Local only — no push / APNs; iOS Notifications permission required. Does not notify on download complete.")
        }
        if notificationAuthStatus == .notDetermined {
            return String(localized: "iOS permission is requested when you turn a notification toggle on, or when a refresh first finds new episodes / a download fails / sync fails / sleep timer ends. Local UserNotifications only — no push / APNs / server-side alerts. No download-complete banners.")
        }
        var parts: [String] = []
        if settings.notifyOnNewEpisodes {
            parts.append(String(localized: "New episodes after refresh (one local banner) → Inbox; needs feed refresh + permission"))
        }
        if settings.notifyOnDownloadErrors {
            parts.append(String(localized: "Download failures → Downloads (title = episode, body = error)"))
        }
        if settings.notifyOnSyncErrors {
            parts.append(String(localized: "Sync / login failures → Settings Sync (short error)"))
        }
        if settings.notifyOnSleepTimerEnd {
            parts.append(String(localized: "Sleep timer end → local banner + foreground haptic (one per fire)"))
        }
        return parts.joined(separator: ". ") + ". " + String(localized: "Local only — no APNs / push / download-complete. OS Notifications permission required.")
    }

    @MainActor
    private func refreshNotificationAuthLabel() async {
        let status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationAuthStatus = .allowed
        case .denied:
            notificationAuthStatus = .denied
        case .notDetermined:
            notificationAuthStatus = .notDetermined
        @unknown default:
            notificationAuthStatus = .unknown
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            Toggle("Delete episode after playing", isOn: $settings.autoDeleteAfterPlaying)
                .accessibilityHint(String(localized: "Removes the offline file when marked played; favorites are kept. Per-podcast override available in Feed settings."))
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
            Picker(String(localized: "Max downloaded episodes"), selection: $settings.downloadEpisodeCacheLimit) {
                ForEach(DownloadEpisodeCacheLimit.allCases) { cap in
                    Text(cap.label).tag(cap)
                }
            }
            .accessibilityLabel(String(localized: "Max downloaded episodes"))
            .accessibilityHint(String(localized: "Maximum number of completed offline downloads to keep. Unlimited by default. Favorites and queued episodes are never auto-deleted by this limit."))
            .onChange(of: settings.downloadEpisodeCacheLimit) { _, _ in
                downloads.runStorageMaintenance()
            }
            Text(episodeCacheHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(episodeCacheHelpText)
            Picker(String(localized: "Parallel downloads"), selection: $settings.maxParallelDownloads) {
                ForEach(MaxParallelDownloads.allCases) { cap in
                    Text(cap.label).tag(cap)
                }
            }
            .accessibilityLabel(String(localized: "Parallel downloads"))
            .accessibilityHint(String(localized: "Maximum number of episode downloads that run at the same time. Default 3."))
            .onChange(of: settings.maxParallelDownloads) { _, _ in
                downloads.pumpWaitingQueue()
            }
            Text(parallelDownloadsHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(parallelDownloadsHelpText)
            Button("Clear downloads", role: .destructive) {
                showClearConfirmation = true
            }
            .disabled(downloads.downloads.isEmpty)
        } header: {
            Text("Downloads / Storage")
        }
    }

    private var episodeCacheHelpText: String {
        String(localized: "When over the episode count, played downloads that are not favorited and not queued are deleted first (oldest file first), then unplayed non-favorite non-queued (LRU). Favorites and queued episodes are never auto-deleted by this cap. Runs after each successful download, when opening Settings, and on launch. Separate from the Max storage byte budget.")
    }

    private var parallelDownloadsHelpText: String {
        String(localized: "Limits how many episode downloads run as active transfers at once (1–5, default 3). Extra downloads wait in memory until a slot frees. Waiting items are not persisted across process death; already-started background URLSession tasks continue after relaunch.")
    }

    private var autoDeleteHelpText: String {
        if settings.autoDeleteAfterPlaying {
            return String(localized: "When an episode is marked played (manual or when playback finishes), its offline file is deleted via DownloadService. The episode row and played status stay. Skips while that local file is still the active player item, and skips favorited / starred episodes. Per-podcast Feed settings can override with Always / Never.")
        }
        return String(localized: "When enabled, offline files are removed after an episode is marked played. Episode metadata and played status are kept. Per-podcast Feed settings can still Always delete for one feed.")
    }

    private var storageUsedLabel: String {
        let used = downloads.storageUsage.usedFormatted
        if let limit = downloads.storageUsage.limitFormatted {
            return "\(used) / \(limit)"
        }
        return String(localized: "\(used) (unlimited)")
    }

    private var evictionHelpText: String {
        String(localized: "When over the limit, played downloads are deleted first (oldest file first), then unplayed (LRU by file date). Runs after each successful download, when opening Settings, and on launch.")
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
                .accessibilityHint(String(localized: "Shows fields to paste a new Podcast Index API key and secret"))
                Button("Clear keys", role: .destructive) {
                    PodcastIndexKeychain.deleteCredentials()
                    podcastIndexKeysSaved = false
                    podcastIndexAPIKeyDraft = ""
                    podcastIndexAPISecretDraft = ""
                    podcastIndexKeyError = nil
                }
                .accessibilityHint(String(localized: "Removes Podcast Index API key and secret from the Keychain"))
            } else {
                SecureField("API key", text: $podcastIndexAPIKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(String(localized: "API key"))
                    .accessibilityHint(String(localized: "Paste your free Podcast Index API key from podcastindex.org"))
                SecureField("API secret", text: $podcastIndexAPISecretDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(String(localized: "API secret"))
                    .accessibilityHint(String(localized: "Paste your free Podcast Index API secret from podcastindex.org"))
                Button("Save keys") {
                    savePodcastIndexKeys()
                }
                .accessibilityHint(String(localized: "Stores the API key and secret in the Keychain on this device only"))
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
        String(localized: "Free API key + secret from podcastindex.org (register / API docs). Stored only in the Keychain — not hardcoded and not shipped with the app. Used by Add podcast → Podcast Index search; Subscribe still follows the feed URL pipeline.")
    }

    private func savePodcastIndexKeys() {
        let key = podcastIndexAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = podcastIndexAPISecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else {
            podcastIndexKeyError = String(localized: "Enter both API key and secret")
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
    private var appStoreRatingSection: some View {
        Section {
            Toggle("Ask for App Store rating", isOn: $settings.askForAppStoreRating)
                .accessibilityHint(String(localized: "May show a review prompt after ten mark-played events once per install."))
            LabeledContent("Mark-played count") {
                Text("\(RatingPromptCoordinator.successfulMarkPlayedCount)/\(RatingPromptCoordinator.threshold)")
                    .foregroundStyle(.secondary)
            }
            .id("rating-count-\(ratingPromptUITick)")
            LabeledContent("Prompt attempted") {
                Text(RatingPromptCoordinator.hasRequestedReview ? "Yes (once)" : "Not yet")
                    .foregroundStyle(.secondary)
            }
            .id("rating-attempted-\(ratingPromptUITick)")
            Button("Reset rating prompt state") {
                RatingPromptCoordinator.resetState()
                ratingPromptUITick += 1
            }
            Text("After \(RatingPromptCoordinator.threshold) newly marked-played episodes (manual or finished playback), AntennaPod may ask iOS to show a rating sheet once per install. iOS decides whether to show it and may suppress the dialog under system limits — we never spam.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("App Store")
        }
    }

    @ViewBuilder
    private var siriShortcutsSection: some View {
        Section {
            Text("Siri / Shortcuts (lite): Play/Pause, Skip forward, Skip back. Also open via URL schemes: antennapod://play, antennapod://pause, antennapod://toggle, antennapod://skip-forward, antennapod://skip-back. Intents open the app and control playback when an episode is already loaded. Not background-only without App Groups.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Siri / Shortcuts")
        }
    }

    @ViewBuilder
    private var homescreenWidgetSection: some View {
        Section {
            Text("Homescreen widget (beta lite): Continue listening shows episode title + podcast + remaining time (wall-clock max(0, duration − position) when duration known; ~ when unknown) from an App Group snapshot. Tap opens antennapod://play. Snapshot may be stale; no live scrubber. Add the widget from the iOS home screen after building with the AntennaPodWidget extension (App Group group.de.danoeh.antennapod.ios).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Homescreen widget")
        }
    }


    @ViewBuilder
    private var appleWatchSection: some View {
        Section {
            Text("Apple Watch (beta lite): Continue listening shows episode title + podcast + remaining time from the same snapshot as the homescreen widget (phone pushes via Watch Connectivity; App Group id group.de.danoeh.antennapod.ios). Play / Open on iPhone remotes antennapod://play on the companion. No independent Watch playback, downloads, or queue — when audio is already playing, use system Now Playing on the Watch. Requires AntennaPodWatch target, Dev Team, and App Group on Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Apple Watch")
        }
    }

    @ViewBuilder
    private var carPlaySection: some View {
        Section {
            Text("CarPlay (honest partial): appears via system Now Playing when audio is playing — MPNowPlayingInfoCenter + remote play/pause/skip/seek (Settings intervals; next/previous → skip). Info.plist already has UIBackgroundModes audio; AVAudioSession category .playback. No custom CarPlay templates / CPTemplate scene / CarPlay entitlement. Apple Watch companion is a separate beta-lite target (Continue listening + Play on iPhone).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("CarPlay")
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
            .accessibilityLabel(String(localized: "Provider"))
            .accessibilityHint(String(localized: "gpodder.net or Nextcloud Gpodder Sync. Switching logs out and clears sync cursors."))

            if gpodder.provider == .nextcloud {
                TextField(
                    GpodderProvider.nextcloudPlaceholderHost,
                    text: $gpodder.host
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .disabled(gpodder.isLoggedIn)
                .accessibilityLabel(String(localized: "Host"))
                .accessibilityHint(String(localized: "Nextcloud server root or full Gpodder Sync API path."))
            } else {
                TextField("Host", text: $gpodder.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(gpodder.isLoggedIn)
                    .accessibilityLabel(String(localized: "Host"))
                    .accessibilityHint(String(localized: "gpodder.net host. Default is https://gpodder.net."))
            }

            TextField("Username", text: $gpodder.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(gpodder.isLoggedIn)
                .accessibilityLabel(String(localized: "Username"))
            if !gpodder.isLoggedIn {
                SecureField("Password", text: $gpodder.passwordDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(String(localized: "Password"))
                    .accessibilityHint(String(localized: "Stored in the Keychain on Login — never in Settings backup."))
            } else {
                LabeledContent("Password") {
                    Text("Stored in Keychain")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Password"))
                .accessibilityValue(String(localized: "Stored in Keychain"))
            }
            TextField("Device name", text: $gpodder.deviceName)
                .disabled(gpodder.isBusy)
                .accessibilityLabel(String(localized: "Device name"))
            LabeledContent("Device id") {
                Text(gpodder.deviceId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            Button("Regenerate device id from name") {
                gpodder.regenerateDeviceIdFromName()
            }
            .disabled(gpodder.isBusy || gpodder.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint(String(localized: "Creates a new device id from the device name and forces a full subscription pull next sync."))
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
                .accessibilityHint(String(localized: "Syncs http(s) subscription feed URLs only. Does not sync episode actions, queue, bookmarks, tags, downloads, or local folders."))
                Button("Logout", role: .destructive) {
                    gpodder.logout()
                }
                .disabled(gpodder.isBusy)
                .accessibilityHint(String(localized: "Removes the Keychain password and clears sync cursors. Host and username stay for re-login."))
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
                .accessibilityHint(String(localized: "Logs in and stores the password in the Keychain. Sync remains subscriptions-only."))
            }
            if let last = gpodder.lastSyncAt {
                LabeledContent("Last sync") {
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                LabeledContent("Last sync") {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text(gpodder.lastSyncStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Sync status"))
                .accessibilityValue(gpodder.lastSyncStatus)
            if let err = gpodder.lastSyncError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel(String(localized: "Sync error"))
                    .accessibilityValue(err)
            }

            LabeledContent("Synced") {
                Text(String(localized: "http(s) subscription feed URLs (additive pull/push)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Synced"))
            .accessibilityValue(String(localized: "http(s) subscription feed URLs (additive pull/push)"))

            LabeledContent("Local only") {
                Text(String(localized: "Episode actions, queue, favorites, bookmarks, tags, downloads, local folders, playback, archive, inbox"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Local only"))
            .accessibilityValue(String(localized: "Episode actions, queue, favorites, bookmarks, tags, downloads, local folders, playback, archive, inbox"))

            Text(gpodderHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Sync coverage help"))
                .accessibilityValue(gpodderHelpText)
        } header: {
            Text("Sync")
        }
    }

    private var gpodderHelpText: String {
        switch gpodder.provider {
        case .gpodderNet:
            return String(localized: "Subscriptions only (beta — not full sync): Synced = http(s) podcast feed URLs (pull missing + push local not on server). Merge is additive — remote removes do not unsubscribe local feeds. Password in Keychain (never plaintext Settings/backup). Not synced (local-only): episode actions (play/download/position), queue, favorites, bookmarks, tags, downloads, local folder feeds, playback progress, archive, inbox. Last sync status and errors stay visible here. Default host https://gpodder.net (editable).")
        case .nextcloud:
            return String(localized: "Nextcloud Gpodder Sync (beta — not full sync): same subscription limits as gpodder.net — additive http(s) feed URLs only; remote removes do not unsubscribe local feeds. Not synced: episode actions, queue, favorites, bookmarks, tags, downloads, local folder feeds, playback, archive, inbox. Enter Nextcloud base (server root or full API root like https://cloud.example.com/index.php/apps/gpoddersync/). HTTP Basic (app password recommended). Requires the Gpodder Sync app on the server. Device id is UI/state only (Nextcloud has no device API). Password in Keychain.")
        }
    }

}


/// Display-only authorization status for Settings → Notifications (not a preference).
private enum NotificationAuthStatus: Equatable {
    case checking
    case allowed
    case denied
    case notDetermined
    case unknown

    var label: String {
        switch self {
        case .checking:
            return String(localized: "Checking…")
        case .allowed:
            return String(localized: "Allowed")
        case .denied:
            return String(localized: "Denied")
        case .notDetermined:
            return String(localized: "Not determined")
        case .unknown:
            return String(localized: "Unknown")
        }
    }
}
