import SwiftUI
import UIKit

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
    @State private var showDeleteAllConfirmation = false
    @State private var showClearEpisodeNotesConfirmation = false
    @State private var showClearFeedNotesConfirmation = false
    @State private var showClearAllBookmarksConfirmation = false
    @State private var showPrivateNotesCopiedAlert = false
    @State private var privateNotesCopyFeedbackTick = 0
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
    /// Proxy password SecureField (write-only; never prefilled from Keychain).
    @State private var httpProxyPasswordDraft = ""
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

    private var privateNotesExportItems: [PrivateNoteExportItem] {
        PrivateNotesExport.items(
            feeds: store.feeds,
            feedSettingsById: store.feedSettingsById,
            episodeNotesById: store.episodePrivateNotesById
        )
    }

    private var privateNotesPlainText: String {
        PrivateNotesExport.plainText(items: privateNotesExportItems)
    }

    private var privateNotesShareText: String {
        PrivateNotesExport.shareText(items: privateNotesExportItems)
    }

    private func copyPrivateNotes() {
        let text = privateNotesPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        showPrivateNotesCopiedAlert = true
        privateNotesCopyFeedbackTick += 1
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
                    "Custom User-Agent",
                    "User-Agent",
                    "AntennaPod-iOS",
                    "HTTP proxy",
                    "Proxy",
                    "Proxy host",
                    "Proxy port",
                    "Proxy username",
                    "Proxy password",
                    "HTTP-Proxy",
                    "Network / Downloads settings are locked. Enter the parental PIN to change these toggles.",
                    "Wi‑Fi / Ethernet vs cellular (system path monitor — no VPN or proxy detection). Auto-download Wi‑Fi only defaults on — skips auto enqueue on cellular. Manual downloads allow cellular by default; Manual download Wi‑Fi only refuses user-initiated downloads on cellular and records an error. Stream Wi‑Fi only (default off) blocks network stream URLs on cellular; local offline files still play. Turn a toggle off to allow cellular for that action.",
                    "Optional override for feed refresh and downloads. Empty uses the app default. Newlines are removed. AVPlayer streaming may still use the system User-Agent. See HTTP proxy for proxy settings.",
                    "Optional HTTP(S) proxy for URLSession clients (feeds, downloads, search, …). AVPlayer streaming may bypass the app proxy. Not VPN detection; not certificate pinning; not SOCKS."
                ) {
                    networkDownloadsSection
                }
                if matchesSearch(
                    "Notifications",
                    "Notify on new episodes",
                    "Notify on download errors",
                    "Notify on download complete",
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
                    "Download all unplayed soft cap",
                    "Delete all downloads",
                    "Unlimited",
                    "Custom (MB)",
                    "10 episodes",
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
                    "Limits how many episode downloads run as active transfers at once (1–5, default 3). Extra downloads wait in memory until a slot frees. Waiting items are not persisted across process death; already-started background URLSession tasks continue after relaunch.",
                    "Limits how many newest unplayed episodes Feed detail Download all unplayed may enqueue at once (10–200, default 50). Always soft-capped — no unlimited. Full-feed eligibility still applies."
                ) {
                    storageSection
                }
                if matchesSearch(
                    "Discovery",
                    "Charts country",
                    "Discover charts count",
                    "charts",
                    "Top lists",
                    "10 podcasts",
                    "25 podcasts",
                    "50 podcasts",
                    "100 podcasts",
                    "API key",
                    "API secret",
                    "Replace keys…",
                    "Clear keys",
                    "Save keys",
                    "Stored in Keychain",
                    "Free API key + secret from podcastindex.org (register / API docs). Stored only in the Keychain — not hardcoded and not shipped with the app. Used by Add podcast → Podcast Index search; Subscribe still follows the feed URL pipeline.",
                    "Used by Home → Discover / Charts and Subscriptions → Discover. Apple iTunes RSS top podcasts (no API key). Automatic uses the device region, or de if unknown.",
                    "How many podcasts the full Discover / Top lists screen loads from Apple iTunes charts. Does not change the Home Discover preview, episode-list or Recently updated Home soft-caps, or Podcast Index search. Default 25. Always capped — no unlimited."
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
                if matchesSearch("Siri / Shortcuts", "Siri / Shortcuts (lite): App Intents — Play, Pause, Play/Pause (toggle), Skip Forward, Skip Back — donated via AppShortcutsProvider for Siri / Shortcuts discoverability. Same actions via URL schemes antennapod://play, antennapod://pause, antennapod://toggle, antennapod://skip-forward, antennapod://skip-back. Intents use openAppWhenRun (open the app) and control playback only when a current episode is already loaded. Not background-only / no App Group shared store. Not episode or feed deep links. Not CarPlay templates (see CarPlay note).") {
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
                    "Choose OPML file…",
                    "HTML lists title, feed URL, and episode count",
                    "author, language, categories, and funding",
                    "Local folder podcasts are omitted from OPML and HTML"
                ) {
                    OpmlImportExportSection()
                }
                if isSearchFiltering && !hasAnyMatchingSettingsSection {
                    ContentUnavailableView(
                        "No matching settings",
                        systemImage: "magnifyingglass",
                        description: Text("No settings rows or sections match your search.")
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "No matching settings"))
                    .accessibilityValue(
                        String(localized: "No settings rows or sections match your search.")
                    )
                    .accessibilityHint(
                        String(localized: "Clear the search field or try another settings term.")
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
            .onChange(of: settings.notifyOnDownloadComplete) { _, enabled in
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
                "Delete all downloads?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete all downloads", role: .destructive) {
                    downloads.deleteAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Deletes \(downloads.downloads.count) completed offline file(s) (\(DownloadStorageUsage.formatBytes(downloads.completedDownloadsByteSize()))), including favorited downloads. Uses the full Downloads catalog. Local files only — keeps played status, queue membership, favorites, archive state, and history. Distinct from Delete played downloads and from Clear queue."
                )
            }
            .confirmationDialog(
                "Clear all episode private notes?",
                isPresented: $showClearEpisodeNotesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear all episode private notes", role: .destructive) {
                    store.clearAllEpisodePrivateNotes()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(store.episodePrivateNotesById.count) local episode private notes from episode-notes.json. Does not clear feed private notes, bookmarks, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                )
            }
            .confirmationDialog(
                "Clear all feed private notes?",
                isPresented: $showClearFeedNotesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear all feed private notes", role: .destructive) {
                    _ = store.clearAllFeedPrivateNotes()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(store.feedPrivateNotesCount) local feed private notes from feed-settings.json. Does not clear episode private notes, bookmarks, pin, tags, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                )
            }
            .confirmationDialog(
                "Clear all bookmarks?",
                isPresented: $showClearAllBookmarksConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear all bookmarks", role: .destructive) {
                    store.clearAllBookmarks()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(store.bookmarksCount) local bookmarks across \(store.bookmarkedEpisodesCount) episodes from bookmarks.json. Does not clear chapters, Share with position, episode or feed private notes, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                )
            }
            .alert(
                String(localized: "Copied"),
                isPresented: $showPrivateNotesCopiedAlert
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(localized: "Private notes copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: privateNotesCopyFeedbackTick)
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
                "Stream Wi‑Fi only",
                "Custom User-Agent",
                "User-Agent",
                "HTTP proxy",
                "Proxy host",
                "Proxy port"
            )
            || matchesSearch(
                "Notifications",
                "Notify on new episodes",
                "Notify on download errors",
                "Notify on download complete",
                "Notify on sync errors",
                "Notify when sleep timer ends",
                "Download errors"
            )
            || matchesSearch(
                "Downloads / Storage",
                "Delete episode after playing",
                "Max storage",
                "Parallel downloads",
                "Download all unplayed soft cap",
                "Delete all downloads"
            )
            || matchesSearch("Discovery", "Charts country", "Discover charts count", "charts", "Top lists", "API key", "API secret")
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
            || matchesSearch("Import / Export", "Export OPML", "Save OPML to Files…", "Import OPML", "Export subscriptions as HTML", "Import from Files", "Choose OPML file…", "HTML lists title, feed URL, and episode count", "author, language, categories, and funding", "Local folder podcasts are omitted from OPML and HTML")
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
            "Home preview rows",
            "Home feed cards",
            "Home Discover charts",
            "Recently updated",
            "Discover",
            "charts",
            "3 rows",
            "5 rows",
            "8 rows",
            "10 rows",
            "Show, hide, and drag-reorder Home tab sections (Continue, Inbox, Queue, Discover, Recently updated, History, Archived, Favorites, Downloads). Search filters section labels; Edit/drag reorder is off while searching. Reset restores the full default layout after confirmation. Empty optional sections still hide when they have no items. History, Archived, Favorites, and Downloads are off by default. Same editor as Home toolbar Configure Home.",
            "How many episode rows each Home section preview shows (Continue, Inbox, Queue, Favorites, History, Archived, Downloads). Soft-cap after search filter — preview is not the full tab. Does not change Discover charts or Recently updated feed cards. Default 5. Always capped — no unlimited.",
            "How many Recently updated feed cards Home shows. Soft-cap after search filter — preview is not the full Subscriptions list. Does not change Discover charts / Top lists or episode-list Home preview rows. Default 5. Always capped — no unlimited.",
            "How many chart rows the Home Discover preview shows. Soft-cap for Home Discover only — not the full Discover / Top lists screen (Settings → Discovery → Discover charts count). Does not change episode-list Home preview rows or Recently updated feed cards. Default 5. Always capped — no unlimited."
        )
    }

    private var matchesQueueSection: Bool {
        matchesSearch(
            "Queue",
            "Lock queue",
            "When on, the Queue tab disables Edit drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Sort by title, Move playing to top, Move playing to bottom, and hides EpisodeRow Move to top / Move to bottom. Enqueue, Play Next, Remove, Remove played, Archive swipe, and Clear queue stay available (reorder lock only — same idea as AntennaPod Android queue lock). Same preference as the Queue toolbar lock button. Default off."
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
            "Caps History-listed episodes in playback.json (played / in-progress). Oldest by lastPlayedAt (else updatedAt) are removed first — same as Remove from history (progress and played flags gone). Unlimited keeps the full list. Does not touch favorites, archive, downloads, or queue. Statistics and Continue listening may lose trimmed episodes. Default Unlimited.",
            "Copy private notes",
            "Share private notes",
            "Private notes",
            "local private notes",
            "plain text",
            "Notes are local until you choose to share; this is not automatic sync.",
            "Clear all episode private notes",
            "Clear all feed private notes",
            "Clear all bookmarks",
            "Clear",
            "clear",
            "notes",
            "private notes",
            "episode notes",
            "episode private notes",
            "feed notes",
            "feed private notes",
            "bookmarks",
            "bookmarks.json",
            "Removes every local episode private note from episode-notes.json. Does not clear feed private notes, bookmarks, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML.",
            "Removes every local feed private note from feed-settings.json. Does not clear episode private notes, bookmarks, pin, tags, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML.",
            "Removes every local bookmark from bookmarks.json. Does not clear chapters, Share with position, episode or feed private notes, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
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
            || matchesPlaybackVolumeBoost
            || matchesPlaybackSleepTimerFade
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
            "When on, video episodes (MIME video/* or mp4/m4v/mov/webm) hide the video surface (artwork instead), disable AVPlayer video tracks, and skip PiP. Does not remux or strip video from the file; background audio continues; streaming/HLS may still download a video stream. Lockscreen / Now Playing stays audio. Default off."
        )
    }

    private var matchesPlaybackVolume: Bool {
        matchesSearch(
            "Volume adaptation",
            "Optimize for speech via the iOS `AVAudioSession` mode (`.spokenAudio`, or `.voiceChat` fallback). When off, audio uses `.default` and video (surface shown) uses `.moviePlayback`. This is a **session mode**, not Android's LoudnessEnhancer gain curve. Default off."
        )
    }

    private var matchesPlaybackVolumeBoost: Bool {
        matchesSearch(
            "Volume boost",
            "Soft gain via `AVMutableAudioMix` track volume (100% = unity, up to 300%). Above 100% may clip or distort. Not ReplayGain / loudness normalization / Android LoudnessEnhancer. Keeps stock AVPlayer (video / PiP / Now Playing). Some streams (e.g. HLS) may ignore audioMix. Sleep-timer fade still uses player volume. Default 100%."
        )
    }

    private var matchesPlaybackSleepTimerFade: Bool {
        matchesSearch(
            "Sleep timer volume fade",
            "When on, clock sleep timer linearly lowers AVPlayer.volume over the last ~10 seconds before pause. End-of-episode / end-of-chapter do not fade. Not equal-loudness / ReplayGain; may be coarse with stock AVPlayer. Volume boost stays on AVAudioMix. Default on (Android always fades)."
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
            "Off",
            "Queue",
            "Same podcast",
            "Off: stop at episode end (mark played / progress still apply). Queue (default): auto-play the next Queue item only. Same podcast: auto-play the next unplayed, non-archived episode of the same feed in that podcast’s episode sort order (per-feed or global) — does not jump the Queue. End-of-episode sleep timer always stops without advancing."
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
            "When on, the mini and full player show remaining time (−m:ss) on the right instead of total duration. Left stays current position. Tap the full-player duration/remaining label to toggle. Default off.",
            "Remaining time respects speed",
            "When on, list and Home remaining-time info bars divide each episode’s remaining by that podcast’s effective playback speed (per-feed override or Default speed, clamped ≥ 0.5). Estimate only — not a live ETA. Does not use the current player session rate for list totals. Mini/full player −remaining and chapter list current remaining use the live session rate (fallback feed/default, 0.5…3.0). Volume boost is not speed. Default off (wall-clock). Widget / Watch Continue stay wall-clock."
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
                String(localized: "Show, hide, and drag-reorder Home tab sections. Same editor as Home toolbar Configure Home. Persisted in AppSettings / backup. Optional History, Archived, Favorites, and Downloads previews are off by default.")
            )
            Text(String(localized: "Show, hide, and drag-reorder Home tab sections (Continue, Inbox, Queue, Discover, Recently updated, History, Archived, Favorites, Downloads). Search filters section labels; Edit/drag reorder is off while searching. Reset restores the full default layout after confirmation. Empty optional sections still hide when they have no items. History, Archived, Favorites, and Downloads are off by default. Same editor as Home toolbar Configure Home."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Home layout help"))
                .accessibilityValue(String(localized: "Show, hide, and drag-reorder Home tab sections (Continue, Inbox, Queue, Discover, Recently updated, History, Archived, Favorites, Downloads). Search filters section labels; Edit/drag reorder is off while searching. Reset restores the full default layout after confirmation. Empty optional sections still hide when they have no items. History, Archived, Favorites, and Downloads are off by default. Same editor as Home toolbar Configure Home."))
            Picker(String(localized: "Home preview rows"), selection: $settings.homePreviewLimit) {
                ForEach(HomePreviewLimit.allCases) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .accessibilityLabel(String(localized: "Home preview rows"))
            .accessibilityValue(settings.homePreviewLimit.label)
            .accessibilityHint(String(localized: "How many episode rows each Home section preview shows (Continue, Inbox, Queue, Favorites, History, Archived, Downloads). Soft-cap after search filter — preview is not the full tab. Does not change Discover charts or Recently updated feed cards. Default 5. Always capped — no unlimited."))
            Text(String(localized: "How many episode rows each Home section preview shows (Continue, Inbox, Queue, Favorites, History, Archived, Downloads). Soft-cap after search filter — preview is not the full tab. Does not change Discover charts or Recently updated feed cards. Default 5. Always capped — no unlimited."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "How many episode rows each Home section preview shows (Continue, Inbox, Queue, Favorites, History, Archived, Downloads). Soft-cap after search filter — preview is not the full tab. Does not change Discover charts or Recently updated feed cards. Default 5. Always capped — no unlimited."))
            Picker(String(localized: "Home feed cards"), selection: $settings.homeFeedsPreviewLimit) {
                ForEach(HomePreviewLimit.allCases) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .accessibilityLabel(String(localized: "Home feed cards"))
            .accessibilityValue(settings.homeFeedsPreviewLimit.label)
            .accessibilityHint(String(localized: "How many Recently updated feed cards Home shows. Soft-cap after search filter — preview is not the full Subscriptions list. Does not change Discover charts / Top lists or episode-list Home preview rows. Default 5. Always capped — no unlimited."))
            Text(String(localized: "How many Recently updated feed cards Home shows. Soft-cap after search filter — preview is not the full Subscriptions list. Does not change Discover charts / Top lists or episode-list Home preview rows. Default 5. Always capped — no unlimited."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "How many Recently updated feed cards Home shows. Soft-cap after search filter — preview is not the full Subscriptions list. Does not change Discover charts / Top lists or episode-list Home preview rows. Default 5. Always capped — no unlimited."))
            Picker(String(localized: "Home Discover charts"), selection: $settings.homeDiscoverPreviewLimit) {
                ForEach(HomePreviewLimit.allCases) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .accessibilityLabel(String(localized: "Home Discover charts"))
            .accessibilityValue(settings.homeDiscoverPreviewLimit.label)
            .accessibilityHint(String(localized: "How many chart rows the Home Discover preview shows. Soft-cap for Home Discover only — not the full Discover / Top lists screen (Settings → Discovery → Discover charts count). Does not change episode-list Home preview rows or Recently updated feed cards. Default 5. Always capped — no unlimited."))
            Text(String(localized: "How many chart rows the Home Discover preview shows. Soft-cap for Home Discover only — not the full Discover / Top lists screen (Settings → Discovery → Discover charts count). Does not change episode-list Home preview rows or Recently updated feed cards. Default 5. Always capped — no unlimited."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "How many chart rows the Home Discover preview shows. Soft-cap for Home Discover only — not the full Discover / Top lists screen (Settings → Discovery → Discover charts count). Does not change episode-list Home preview rows or Recently updated feed cards. Default 5. Always capped — no unlimited."))
        }
    }

    @ViewBuilder
    private var queueSettingsSection: some View {
        Section("Queue") {
            Toggle("Lock queue", isOn: $settings.queueLocked)
                .accessibilityHint(String(localized: "When on, disables Queue drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Sort by title, Move playing to top, Move playing to bottom, and Move to top or bottom. Enqueue, Play Next, Remove, Remove played, and Clear queue still work. Default off."))
            Text("When on, the Queue tab disables Edit drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Sort by title, Move playing to top, Move playing to bottom, and hides EpisodeRow Move to top / Move to bottom. Enqueue, Play Next, Remove, Remove played, Archive swipe, and Clear queue stay available (reorder lock only — same idea as AntennaPod Android queue lock). Same preference as the Queue toolbar lock button. Default off.")
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
            if matchesSearch(
                "Library",
                "Copy private notes",
                "Share private notes",
                "Private notes",
                "local private notes",
                "plain text",
                "Notes are local until you choose to share; this is not automatic sync."
            ) {
                Button {
                    copyPrivateNotes()
                } label: {
                    Label(String(localized: "Copy private notes"), systemImage: "doc.on.clipboard")
                }
                .disabled(privateNotesExportItems.isEmpty)
                .accessibilityLabel(String(localized: "Copy private notes"))
                .accessibilityValue(
                    privateNotesExportItems.isEmpty
                        ? String(localized: "No private notes")
                        : String(localized: "\(privateNotesExportItems.count) private notes")
                )
                .accessibilityHint(String(localized: "Copies all non-empty feed and episode private notes as plain text; notes stay local until you choose to share"))

                ShareLink(
                    item: privateNotesShareText,
                    subject: Text(String(localized: "Private notes"))
                ) {
                    Label(String(localized: "Share private notes"), systemImage: "square.and.arrow.up")
                }
                .disabled(privateNotesExportItems.isEmpty)
                .accessibilityLabel(String(localized: "Share private notes"))
                .accessibilityValue(
                    privateNotesExportItems.isEmpty
                        ? String(localized: "No private notes")
                        : String(localized: "\(privateNotesExportItems.count) private notes")
                )
                .accessibilityHint(String(localized: "Opens the system share sheet with all non-empty feed and episode private notes as plain text; sharing is your choice"))

                Text(String(localized: "Exports all non-empty local feed and episode private notes as plain text. Copy stays in the pasteboard; Share opens the system sheet. Notes are local until you choose to share; this is not automatic sync."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesSearch(
                "Library",
                "Clear all episode private notes",
                "Clear",
                "clear",
                "notes",
                "private notes",
                "episode notes",
                "episode private notes",
                "Removes every local episode private note from episode-notes.json. Does not clear feed private notes, bookmarks, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
            ) {
                Button("Clear all episode private notes", role: .destructive) {
                    showClearEpisodeNotesConfirmation = true
                }
                .disabled(store.episodePrivateNotesById.isEmpty)
                .accessibilityLabel(String(localized: "Clear all episode private notes"))
                .accessibilityValue(
                    store.episodePrivateNotesById.isEmpty
                        ? String(localized: "No episode private notes")
                        : String(
                            localized: "\(store.episodePrivateNotesById.count) episode private notes"
                        )
                )
                .accessibilityHint(
                    String(
                        localized: "Removes every local episode private note after confirmation. Does not clear feed notes, bookmarks, favorites, downloads, queue, or history."
                    )
                )
                Text(
                    store.episodePrivateNotesById.isEmpty
                        ? String(
                            localized: "No episode private notes saved. Removes every local episode private note from episode-notes.json when any exist. Does not clear feed private notes, bookmarks, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                        )
                        : String(
                            localized: "\(store.episodePrivateNotesById.count) episode private notes saved. Removes every local episode private note from episode-notes.json. Does not clear feed private notes, bookmarks, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if matchesSearch(
                "Library",
                "Clear all feed private notes",
                "Clear",
                "clear",
                "notes",
                "private notes",
                "feed notes",
                "feed private notes",
                "Removes every local feed private note from feed-settings.json. Does not clear episode private notes, bookmarks, pin, tags, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
            ) {
                Button("Clear all feed private notes", role: .destructive) {
                    showClearFeedNotesConfirmation = true
                }
                .disabled(store.feedPrivateNotesCount == 0)
                .accessibilityLabel(String(localized: "Clear all feed private notes"))
                .accessibilityValue(
                    store.feedPrivateNotesCount == 0
                        ? String(localized: "No feed private notes")
                        : String(
                            localized: "\(store.feedPrivateNotesCount) feed private notes"
                        )
                )
                .accessibilityHint(
                    String(
                        localized: "Removes every local feed private note after confirmation. Does not clear episode notes, bookmarks, pin, tags, favorites, downloads, queue, or history."
                    )
                )
                Text(
                    store.feedPrivateNotesCount == 0
                        ? String(
                            localized: "No feed private notes saved. Removes every local feed private note from feed-settings.json when any exist. Does not clear episode private notes, bookmarks, pin, tags, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                        )
                        : String(
                            localized: "\(store.feedPrivateNotesCount) feed private notes saved. Removes every local feed private note from feed-settings.json. Does not clear episode private notes, bookmarks, pin, tags, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if matchesSearch(
                "Library",
                "Clear all bookmarks",
                "Clear",
                "clear",
                "bookmarks",
                "bookmarks.json",
                "Lesezeichen",
                "Removes every local bookmark from bookmarks.json. Does not clear chapters, Share with position, episode or feed private notes, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
            ) {
                Button("Clear all bookmarks", role: .destructive) {
                    showClearAllBookmarksConfirmation = true
                }
                .disabled(store.bookmarksCount == 0)
                .accessibilityLabel(String(localized: "Clear all bookmarks"))
                .accessibilityValue(
                    store.bookmarksCount == 0
                        ? String(localized: "No bookmarks")
                        : String(
                            localized: "\(store.bookmarksCount) bookmarks across \(store.bookmarkedEpisodesCount) episodes"
                        )
                )
                .accessibilityHint(
                    String(
                        localized: "Removes every local bookmark after confirmation. Does not clear chapters, Share with position, private notes, favorites, downloads, queue, or history."
                    )
                )
                Text(
                    store.bookmarksCount == 0
                        ? String(
                            localized: "No bookmarks saved. Removes every local bookmark from bookmarks.json when any exist. Does not clear chapters, Share with position, episode or feed private notes, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                        )
                        : String(
                            localized: "\(store.bookmarksCount) bookmarks across \(store.bookmarkedEpisodesCount) episodes. Removes every local bookmark from bookmarks.json. Does not clear chapters, Share with position, episode or feed private notes, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .accessibilityHint(String(localized: "Hides the video surface, disables video tracks, and shows artwork. Lockscreen stays audio. Does not strip video from the file."))
                Text("When on, video episodes (MIME video/* or mp4/m4v/mov/webm) hide the video surface (artwork instead), disable AVPlayer video tracks, and skip PiP. Does not remux or strip video from the file; background audio continues; streaming/HLS may still download a video stream. Lockscreen / Now Playing stays audio. Default off.")
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
            if matchesPlaybackVolumeBoost {
                Picker("Volume boost", selection: $settings.volumeBoostPercent) {
                    ForEach(AppSettings.volumeBoostPresets, id: \.self) { percent in
                        Text(AppSettings.volumeBoostLabel(percent)).tag(percent)
                    }
                }
                .accessibilityHint(String(localized: "Soft gain via AVAudioMix. Above 100% may clip or distort. Not ReplayGain or LoudnessEnhancer. Default 100%."))
                Text("Soft gain via `AVMutableAudioMix` track volume (100% = unity, up to 300%). Above 100% may clip or distort. Not ReplayGain / loudness normalization / Android LoudnessEnhancer. Keeps stock AVPlayer (video / PiP / Now Playing). Some streams (e.g. HLS) may ignore audioMix. Sleep-timer fade still uses player volume. Default 100%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackSleepTimerFade {
                Toggle("Sleep timer volume fade", isOn: $settings.sleepTimerFadeEnabled)
                    .accessibilityHint(String(localized: "Lowers volume over the last ~10 seconds of a clock sleep timer. End of episode or chapter do not fade. Default on."))
                Text("When on, clock sleep timer linearly lowers `AVPlayer.volume` over the last ~10 seconds before pause (Android `NOTIFICATION_THRESHOLD`). End-of-episode / end-of-chapter do **not** fade. Soft player volume only — **not** equal-loudness / ReplayGain; may be coarse with stock `AVPlayer`. Volume boost stays on `AVAudioMix`. Pause / seek / cancel timer restores pre-fade volume. Default **on** (Android always fades; no Android off-toggle).")
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
                Picker("Continuous playback", selection: $settings.continuousPlaybackMode) {
                    ForEach(ContinuousPlaybackMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .accessibilityHint(String(localized: "Off stops at episode end. Queue (default) plays the next Queue item. Same podcast plays the next unplayed episode of this feed by episode sort — not the Queue."))
                Text("Off: stop at episode end (mark played / progress still apply). Queue (default): auto-play the next Queue item only. Same podcast: auto-play the next unplayed, non-archived episode of the same feed in that podcast’s episode sort order (per-feed or global) — does not jump the Queue. End-of-episode sleep timer always stops without advancing.")
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
                Toggle("Remaining time respects speed", isOn: $settings.remainingTimeRespectsSpeed)
                    .accessibilityHint(String(localized: "When on, list remaining-time bars use each podcast’s playback speed; mini/full −remaining and chapter remaining use the live session rate. Default off."))
                Text("When on, list and Home remaining-time info bars divide each episode’s remaining by that podcast’s effective playback speed (per-feed override or Default speed, clamped ≥ 0.5). Estimate only — not a live ETA. Does not use the current player session rate for list totals. Mini/full player −remaining and chapter list current remaining use the live session rate (fallback feed/default, 0.5…3.0). Volume boost is not speed. Default off (wall-clock). Widget / Watch Continue stay wall-clock.")
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
            .accessibilityLabel(String(localized: "Refresh interval"))
            .accessibilityValue(settings.refreshInterval.label)
            .accessibilityHint(refreshIntervalAccessibilityHint)
            // Global bulk-refresh stamp — not each podcast's Last refreshed.
            // Visible relative time stays; VoiceOver uses Never vs absolute finish time.
            LabeledContent("Last refresh") {
                if let last = settings.lastFeedRefreshAt {
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Last refresh"))
            .accessibilityValue(lastRefreshAccessibilityValue)
            .accessibilityHint(lastRefreshAccessibilityHint)
            Text(refreshHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Feed refresh help"))
                .accessibilityValue(refreshHelpText)
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

    /// VoiceOver for Settings → Last refresh. Never means no bulk refresh has finished;
    /// a date is the last Refresh-all completion, not a per-podcast stamp.
    private var lastRefreshAccessibilityValue: String {
        guard let last = settings.lastFeedRefreshAt else {
            return String(localized: "Never. No bulk subscription refresh has finished yet. This is not a per-podcast Last refreshed time, and no timestamp is invented.")
        }
        let formatted = last.formatted(date: .abbreviated, time: .shortened)
        return String(
            format: String(localized: "Bulk refresh finished %@. The stamp is written when Refresh all finishes, even if some podcasts failed. It is not each podcast's Last refreshed time."),
            formatted
        )
    }

    private var lastRefreshAccessibilityHint: String {
        String(localized: "Pull to refresh on Subscriptions, Home, or Inbox, or use Refresh all. A timed interval also checks when you open the app. iOS Background App Refresh is not enabled in this beta.")
    }

    private var refreshIntervalAccessibilityHint: String {
        String(localized: "Manual only refreshes when you pull to refresh or refresh a podcast. A timed interval runs when you open the app, not as iOS Background App Refresh. Per-podcast Keep updated Never still skips that podcast.")
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

            TextField(
                String(localized: "Custom User-Agent"),
                text: $settings.customUserAgent,
                prompt: Text(AppUserAgent.defaultValue)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(String(localized: "Custom User-Agent"))
            .accessibilityHint(String(localized: "Optional override for feed refresh and downloads. Empty uses the app default. Newlines are removed. AVPlayer streaming may still use the system User-Agent. See HTTP proxy for proxy settings."))
            .accessibilityValue(
                settings.customUserAgent.isEmpty
                    ? String(localized: "Using app default")
                    : settings.customUserAgent
            )

            LabeledContent(String(localized: "Effective User-Agent")) {
                Text(settings.effectiveUserAgent)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Effective User-Agent"))
            .accessibilityValue(settings.effectiveUserAgent)

            Text(customUserAgentHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(customUserAgentHelpText)

            Toggle(String(localized: "HTTP proxy"), isOn: $settings.httpProxyEnabled)
                .accessibilityLabel(String(localized: "HTTP proxy"))
                .accessibilityHint(String(localized: "When on and host plus port are valid, URLSession clients use this HTTP(S) proxy. AVPlayer streaming may bypass it."))

            if settings.httpProxyEnabled {
                TextField(
                    String(localized: "Proxy host"),
                    text: $settings.httpProxyHost,
                    prompt: Text(String(localized: "example.com"))
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityLabel(String(localized: "Proxy host"))
                .accessibilityHint(String(localized: "Hostname without http or https. Empty host disables the proxy."))

                TextField(
                    String(localized: "Proxy port"),
                    value: $settings.httpProxyPort,
                    format: .number.grouping(.never),
                    prompt: Text("8080")
                )
                .keyboardType(.numberPad)
                .accessibilityLabel(String(localized: "Proxy port"))
                .accessibilityHint(String(localized: "Port from 1 to 65535. Invalid port disables the proxy."))
                .accessibilityValue("\(settings.httpProxyPort)")

                TextField(
                    String(localized: "Proxy username"),
                    text: $settings.httpProxyUsername,
                    prompt: Text(String(localized: "Optional"))
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(String(localized: "Proxy username"))
                .accessibilityHint(String(localized: "Optional. Password is stored in the Keychain only."))

                SecureField(
                    String(localized: "Proxy password"),
                    text: $httpProxyPasswordDraft,
                    prompt: Text(
                        settings.httpProxyHasStoredPassword
                            ? String(localized: "Stored in Keychain")
                            : String(localized: "Optional")
                    )
                )
                .textContentType(.password)
                .accessibilityLabel(String(localized: "Proxy password"))
                .accessibilityHint(String(localized: "Optional. Saved to Keychain only — never in backup JSON. Leave blank to keep the stored password."))
                .onSubmit {
                    commitHTTPProxyPasswordDraft()
                }

                HStack {
                    Button(String(localized: "Save password")) {
                        commitHTTPProxyPasswordDraft()
                    }
                    .disabled(httpProxyPasswordDraft.isEmpty)
                    if settings.httpProxyHasStoredPassword {
                        Button(String(localized: "Clear password"), role: .destructive) {
                            settings.clearHTTPProxyPassword()
                            httpProxyPasswordDraft = ""
                        }
                    }
                }
                .font(.subheadline)
            }

            Text(httpProxyHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(httpProxyHelpText)

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

    private var customUserAgentHelpText: String {
        String(localized: "Optional override for feed refresh and downloads. Empty uses the app default. Newlines are removed. AVPlayer streaming may still use the system User-Agent. See HTTP proxy for proxy settings.")
    }

    private var httpProxyHelpText: String {
        String(localized: "Optional HTTP(S) proxy for URLSession clients (feeds, downloads, search, …). AVPlayer streaming may bypass the app proxy. Not VPN detection; not certificate pinning; not SOCKS.")
    }

    private func commitHTTPProxyPasswordDraft() {
        let draft = httpProxyPasswordDraft
        guard !draft.isEmpty else { return }
        settings.setHTTPProxyPassword(draft)
        httpProxyPasswordDraft = ""
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle("Notify on new episodes", isOn: $settings.notifyOnNewEpisodes)
                .accessibilityHint(String(localized: "Master switch for local new-episode notifications after refresh. Per-podcast Off silences that feed; per-podcast On is ignored while this is off. No push server."))
            Toggle("Notify on download errors", isOn: $settings.notifyOnDownloadErrors)
                .accessibilityHint(String(localized: "Local notifications when a download fails — not when a download completes successfully."))
            Toggle("Notify on download complete", isOn: $settings.notifyOnDownloadComplete)
                .accessibilityHint(String(localized: "Optional local notifications when a download finishes successfully. Default off — quieter than download errors."))
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
                Text(String(localized: "New episodes after refresh (one local banner → Inbox); download failures → Downloads; download complete (optional, default off) → Downloads; sync/login failures → Settings Sync; sleep timer end (banner + foreground haptic)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Notifies"))
            .accessibilityValue(String(localized: "New episodes after refresh (one local banner → Inbox); download failures → Downloads; download complete (optional, default off) → Downloads; sync/login failures → Settings Sync; sleep timer end (banner + foreground haptic)"))

            LabeledContent("Does not notify") {
                Text(String(localized: "No push / APNs / server-side alerts. Download-complete banners only when that optional toggle is on (default off). No episode-level deep link for new episodes (Inbox only). Needs an in-app refresh, download, sync, or sleep-timer fire — not a remote push."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Does not notify"))
            .accessibilityValue(String(localized: "No push / APNs / server-side alerts. Download-complete banners only when that optional toggle is on (default off). No episode-level deep link for new episodes (Inbox only). Needs an in-app refresh, download, sync, or sleep-timer fire — not a remote push."))

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
            return String(localized: "Notification permission was denied. AntennaPod will not show banners until you allow Notifications in iOS Settings (Open iOS Settings). Toggles stay on so your preference is clear. Local UserNotifications only — never push / APNs / server-side alerts. Download-complete is optional (default off).")
        }
        if !settings.notifyOnNewEpisodes && !settings.notifyOnDownloadErrors && !settings.notifyOnDownloadComplete && !settings.notifyOnSyncErrors && !settings.notifyOnSleepTimerEnd {
            return String(localized: "When enabled: new episodes after refresh (one aggregated local banner → Inbox), download failures → Downloads, download complete (optional, default off) → Downloads, gpodder/Nextcloud login or sync failures → Settings Sync, and/or sleep timer end (banner + foreground haptic). Local only — no push / APNs; iOS Notifications permission required.")
        }
        if notificationAuthStatus == .notDetermined {
            return String(localized: "iOS permission is requested when you turn a notification toggle on, or when a refresh first finds new episodes / a download fails or completes / sync fails / sleep timer ends. Local UserNotifications only — no push / APNs / server-side alerts. Download-complete is optional (default off).")
        }
        var parts: [String] = []
        if settings.notifyOnNewEpisodes {
            parts.append(String(localized: "New episodes after refresh (one local banner) → Inbox; needs feed refresh + permission"))
        }
        if settings.notifyOnDownloadErrors {
            parts.append(String(localized: "Download failures → Downloads (title = episode, body = error)"))
        }
        if settings.notifyOnDownloadComplete {
            parts.append(String(localized: "Download complete → Downloads (title = episode, body = feed)"))
        }
        if settings.notifyOnSyncErrors {
            parts.append(String(localized: "Sync / login failures → Settings Sync (short error)"))
        }
        if settings.notifyOnSleepTimerEnd {
            parts.append(String(localized: "Sleep timer end → local banner + foreground haptic (one per fire)"))
        }
        return parts.joined(separator: ". ") + ". " + String(localized: "Local only — no APNs / push. OS Notifications permission required.")
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
            Picker(String(localized: "Download all unplayed soft cap"), selection: $settings.feedDownloadUnplayedSoftCap) {
                ForEach(FeedDownloadUnplayedSoftCap.allCases) { cap in
                    Text(cap.label).tag(cap)
                }
            }
            .accessibilityLabel(String(localized: "Download all unplayed soft cap"))
            .accessibilityHint(String(localized: "Maximum number of newest unplayed episodes Feed detail Download all unplayed may enqueue at once. Default 50. Always soft-capped — no unlimited."))
            Text(feedDownloadUnplayedSoftCapHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(feedDownloadUnplayedSoftCapHelpText)
            Button("Delete all downloads", role: .destructive) {
                showDeleteAllConfirmation = true
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

    private var feedDownloadUnplayedSoftCapHelpText: String {
        String(localized: "Limits how many newest unplayed episodes Feed detail Download all unplayed may enqueue at once (10–200, default 50). Always soft-capped — no unlimited. Full-feed eligibility still applies.")
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

            Picker(String(localized: "Discover charts count"), selection: $settings.discoverChartsLimit) {
                ForEach(DiscoverChartsLimit.allCases) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .accessibilityLabel(String(localized: "Discover charts count"))
            .accessibilityValue(settings.discoverChartsLimit.label)
            .accessibilityHint(String(localized: "How many podcasts the full Discover / Top lists screen loads from Apple iTunes charts. Does not change the Home Discover preview, episode-list or Recently updated Home soft-caps, or Podcast Index search. Default 25. Always capped — no unlimited."))
            Text(String(localized: "How many podcasts the full Discover / Top lists screen loads from Apple iTunes charts. Does not change the Home Discover preview, episode-list or Recently updated Home soft-caps, or Podcast Index search. Default 25. Always capped — no unlimited."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "How many podcasts the full Discover / Top lists screen loads from Apple iTunes charts. Does not change the Home Discover preview, episode-list or Recently updated Home soft-caps, or Podcast Index search. Default 25. Always capped — no unlimited."))

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
            Text("Siri / Shortcuts (lite): App Intents — Play, Pause, Play/Pause (toggle), Skip Forward, Skip Back — donated via AppShortcutsProvider for Siri / Shortcuts discoverability. Same actions via URL schemes antennapod://play, antennapod://pause, antennapod://toggle, antennapod://skip-forward, antennapod://skip-back. Intents use openAppWhenRun (open the app) and control playback only when a current episode is already loaded. Not background-only / no App Group shared store. Not episode or feed deep links. Not CarPlay templates (see CarPlay note).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Siri / Shortcuts"))
                .accessibilityHint(String(localized: "Lite App Intents Play Pause Skip; opens app; needs current episode; not CarPlay templates."))
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
