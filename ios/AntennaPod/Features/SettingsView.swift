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
        case .unlimited: return String(localized: "Unlimited")
        case .gb1: return "1 GB"
        case .gb5: return "5 GB"
        case .gb10: return "10 GB"
        case .custom: return String(localized: "Custom (MB)")
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
    // Typed text for fields whose AppSettings didSet trims. Binding them directly
    // dropped a space as soon as it was typed at the end ("MyApp/1.0 " → "MyApp/1.0").
    @State private var customUserAgentDraft = ""
    @State private var httpProxyUsernameDraft = ""
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

    /// Sync-error notification tap: reveal Sync even when this tab is first created by the
    /// tap, or when a settings search has removed the `settings-sync` anchor from the tree.
    private func scrollToSyncSectionIfPending(_ proxy: ScrollViewProxy) {
        guard notificationDeepLink.consumeSettingsSyncOpenToken() else { return }
        debounceTask?.cancel()
        if !searchText.isEmpty || isSearchFiltering {
            searchText = ""
            debouncedQuery = ""
        }
        // Defer slightly so the Settings tab is visible and the Sync section is mounted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation {
                proxy.scrollTo("settings-sync", anchor: .top)
            }
        }
    }

    /// Case-insensitive match on source keys and their localized catalog values (EN/DE).
    private func matchesSearch(_ keys: String...) -> Bool {
        matchesSearch(Array(keys))
    }

    private func matchesSearch(_ keys: [String]) -> Bool {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return keys.contains { key in
            if key.localizedSearchContains(q) { return true }
            let localized = String(localized: String.LocalizationValue(key))
            return localized.localizedSearchContains(q)
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
                    "Wi‑Fi / Ethernet vs cellular (system path monitor — no VPN or proxy detection). Auto-download Wi‑Fi only defaults on — skips auto enqueue on cellular. Manual downloads allow cellular by default; Manual download Wi‑Fi only refuses user-initiated downloads on cellular and records an error. Stream Wi‑Fi only (default off) blocks network stream URLs on cellular; local offline files still play. Turn a toggle off to allow cellular for that action. Feed refresh (Refresh all, pull-to-refresh, timed interval, and single-podcast refresh) is not limited by these toggles and may use cellular — there is no separate Mobile updates setting.",
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
                    "When over the limit, played downloads that are not favorited and not queued are deleted first (oldest file first), then unplayed non-favorite non-queued (LRU by file date). Favorites and queued episodes are never auto-deleted by this budget. Runs after each successful download, when opening Settings, and on launch.",
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
                if matchesSearch("Siri / Shortcuts", "Siri / Shortcuts (lite): App Intents — Play, Pause, Play/Pause (toggle), Skip Forward, Skip Back — donated via AppShortcutsProvider for Siri / Shortcuts discoverability. Same actions via URL schemes antennapod://play, antennapod://pause, antennapod://toggle, antennapod://skip-forward, antennapod://skip-back. Intents use openAppWhenRun (open the app). Play and Play/Pause play the loaded episode, or after a cold launch the previous run’s unplayed episode shown paused in the mini player. Skip Forward and Skip Back need a loaded episode. Not background-only / no App Group shared store. Not episode or feed deep links. Not CarPlay templates (see CarPlay note).") {
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
                // Tab content is created on first selection, so a sync-error tap that
                // switches here never delivers onChange for the token already set.
                scrollToSyncSectionIfPending(proxy)
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
            .onChange(of: notificationDeepLink.settingsSyncOpenToken) { _, _ in
                scrollToSyncSectionIfPending(proxy)
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
                    "Deletes \(downloads.downloads.count) completed offline file(s) (\(DownloadStorageUsage.formatBytes(downloads.completedDownloadsByteSize()))), including favorited downloads. Uses the full Downloads catalog. Queued episodes and the episode playing from a download can lose their offline file (queue membership stays; playback continues from the stream). Local files only — keeps played status, queue membership, favorites, archive state, and history. Distinct from Delete played downloads and from Clear queue."
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
                        localized: "Asks for confirmation, then removes every local episode private note from episode-notes.json. Does not clear feed private notes, bookmarks, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
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
                        localized: "Asks for confirmation, then removes every local feed private note from feed-settings.json. Does not clear episode private notes, bookmarks, pin, tags, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
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
                        localized: "Asks for confirmation, then removes every local bookmark from bookmarks.json. Does not clear chapters, Share with position, episode or feed private notes, favorites, archive, downloads, queue, or history. Local only — not RSS / gpodder / OPML."
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
                .accessibilityLabel(String(localized: "Default speed"))
                .accessibilityValue(defaultSpeedAccessibilityValue)
                .accessibilityHint(defaultSpeedAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Rewind"))
                .accessibilityValue(rewindIntervalAccessibilityValue)
                .accessibilityHint(rewindIntervalAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Fast-forward"))
                .accessibilityValue(fastForwardIntervalAccessibilityValue)
                .accessibilityHint(fastForwardIntervalAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Skip intro"))
                .accessibilityValue(skipIntroAccessibilityValue)
                .accessibilityHint(skipIntroAccessibilityHint)
                Picker("Skip outro", selection: $settings.skipOutroSeconds) {
                    ForEach(AppSettings.skipIntroOutroPresets, id: \.self) { secs in
                        Text(AppSettings.skipIntroOutroLabel(secs)).tag(secs)
                    }
                }
                .accessibilityLabel(String(localized: "Skip outro"))
                .accessibilityValue(skipOutroAccessibilityValue)
                .accessibilityHint(skipOutroAccessibilityHint)
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
                    .accessibilityLabel(String(localized: "Volume adaptation"))
                    .accessibilityValue(volumeAdaptationAccessibilityValue)
                    .accessibilityHint(volumeAdaptationAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Volume boost"))
                .accessibilityValue(volumeBoostAccessibilityValue)
                .accessibilityHint(volumeBoostAccessibilityHint)
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
                    .accessibilityLabel(String(localized: "Skip silence"))
                    .accessibilityValue(skipSilenceAccessibilityValue)
                    .accessibilityHint(skipSilenceAccessibilityHint)
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
                    .accessibilityLabel(String(localized: "Preserve pitch"))
                    .accessibilityValue(preservePitchAccessibilityValue)
                    .accessibilityHint(preservePitchAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Continuous playback"))
                .accessibilityValue(continuousPlaybackAccessibilityValue)
                .accessibilityHint(continuousPlaybackAccessibilityHint)
                Text("Off: stop at episode end (mark played / progress still apply). Queue (default): auto-play the next Queue item only. Same podcast: auto-play the next unplayed, non-archived episode of the same feed in that podcast’s episode sort order (per-feed or global) — does not jump the Queue. End-of-episode sleep timer always stops without advancing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackResetPosition {
                Toggle("Reset position when marked played", isOn: $settings.resetPositionWhenMarkedPlayed)
                    .accessibilityLabel(String(localized: "Reset position when marked played"))
                    .accessibilityValue(resetPositionWhenMarkedPlayedAccessibilityValue)
                    .accessibilityHint(resetPositionWhenMarkedPlayedAccessibilityHint)
                Text("When on, marking an episode played clears its saved playback position to 0 (resume from start later). When off, the position is kept so Mark unplayed can resume. Applies to manual mark, mark-all, smart mark, and natural end. Default on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if matchesPlaybackRemaining {
                Toggle("Show remaining time", isOn: $settings.showRemainingTime)
                    .accessibilityLabel(String(localized: "Show remaining time"))
                    .accessibilityValue(showRemainingTimeAccessibilityValue)
                    .accessibilityHint(showRemainingTimeAccessibilityHint)
                Text("When on, the mini and full player show remaining time (−m:ss) on the right instead of total duration. Left stays current position. Tap the full-player duration/remaining label to toggle. Default off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Remaining time respects speed", isOn: $settings.remainingTimeRespectsSpeed)
                    .accessibilityLabel(String(localized: "Remaining time respects speed"))
                    .accessibilityValue(remainingTimeRespectsSpeedAccessibilityValue)
                    .accessibilityHint(remainingTimeRespectsSpeedAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Rewind after pause"))
                .accessibilityValue(rewindAfterPauseAccessibilityValue)
                .accessibilityHint(rewindAfterPauseAccessibilityHint)
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
                .accessibilityLabel(String(localized: "Smart mark as played"))
                .accessibilityValue(smartMarkAsPlayedAccessibilityValue)
                .accessibilityHint(smartMarkAsPlayedAccessibilityHint)
                Button(String(localized: "Custom…")) {
                    showCustomSmartMark = true
                }
                .accessibilityLabel(String(localized: "Custom smart mark"))
                .accessibilityHint(String(localized: "Opens a sheet to set a custom smart mark threshold between 1 and 600 seconds remaining. Does not mark an episode played now. Presets stay in the picker. Off is not available here."))
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
            .accessibilityValue(refreshIntervalAccessibilityValue)
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

    /// VoiceOver for Settings → Skip silence. On is a saved preference only.
    /// Stock AVPlayer does not skip silence in this beta, so On must not sound like it works.
    private var skipSilenceAccessibilityValue: String {
        if settings.skipSilenceEnabled {
            return String(localized: "On. The preference is saved, but silence is not skipped on stock AVPlayer in this beta. Turning this on does not change playback, speed, or downloads, and it is not Preserve pitch.")
        }
        return String(localized: "Off. Silence is not skipped. This is the default. Turning this off does not change playback, and no skipped-silence time is invented.")
    }

    private var skipSilenceAccessibilityHint: String {
        String(localized: "Saved preference only. This beta does not skip silence on stock AVPlayer, because a custom audio engine would break the video surface, Now Playing, and playback rate. The switch does not start playback. Not Preserve pitch. Default off.")
    }

    /// VoiceOver for Settings → Preserve pitch. On is stock AVPlayer time-domain
    /// correction when speed is not 1×. Off is varispeed. Neither state skips silence.
    private var preservePitchAccessibilityValue: String {
        if settings.preservePitchEnabled {
            return String(localized: "On. When playback speed is not 1×, stock AVPlayer keeps a natural pitch. This is the default. At 1× the pitch stays the same either way. If an item is already loaded, the change applies to that item; otherwise it is saved for the next one. This does not start playback, skip silence, seek, or download. Not Android ExoPlayer or Sonic.")
        }
        return String(localized: "Off. When playback speed is not 1×, pitch follows the speed on stock AVPlayer, so faster sounds higher and slower sounds lower. At 1× the pitch stays the same either way. If an item is already loaded, the change applies to that item; otherwise it is saved for the next one. This does not start playback, skip silence, seek, or download. Not Android ExoPlayer or Sonic.")
    }

    private var preservePitchAccessibilityHint: String {
        String(localized: "On keeps natural pitch when speed is not 1×. Off lets pitch follow speed. The switch does not start playback, skip silence, or download anything. Default on.")
    }

    /// VoiceOver for Settings → Continuous playback. Each value names the saved mode
    /// and what episode end actually does. None of them invent a next episode.
    private var continuousPlaybackAccessibilityValue: String {
        switch settings.continuousPlaybackMode {
        case .off:
            return String(localized: "Off. When an episode ends, playback stops. Mark played and saved progress still apply. Nothing is added to the Queue or downloaded, and no next episode is invented. This is not the default. An end-of-episode or last-chapter sleep timer also stops. End of queue still continues through the Queue only. Changing this does not start playback.")
        case .queue:
            return String(localized: "Queue. This is the default. When an episode ends, only the next Queue item starts, if one exists and playback can start. The feed list is not walked. If there is no next Queue item, or it cannot start, playback stops and no episode is invented. An end-of-episode or last-chapter sleep timer still stops without advancing. Changing this does not start playback.")
        case .samePodcast:
            return String(localized: "Same podcast. When an episode ends, the next unplayed, non-archived episode of the same podcast starts, if one exists and playback can start, using that podcast’s episode sort, forward only, with no wrap. The Queue is not jumped. If none exists, or it cannot start, playback stops and no episode is invented. This is not the default. An end-of-episode or last-chapter sleep timer still stops without advancing. End of queue still continues through the Queue only. Changing this does not start playback.")
        }
    }

    private var continuousPlaybackAccessibilityHint: String {
        String(localized: "Off stops at episode end. Queue, the default, plays the next Queue item only. Same podcast plays the next unplayed, non-archived episode of this feed by episode sort, forward only, no wrap, and does not jump the Queue. Mark played and progress still apply in every mode. An end-of-episode or last-chapter sleep timer still stops without advancing. End of queue still advances through the Queue only, even when this is Off or Same podcast. Changing this does not start playback, seek, or download, and it does not invent a next episode.")
    }

    /// VoiceOver for Settings → Rewind. Names the saved interval and whether it is
    /// the 10-second default. Changing the picker does not seek.
    private var rewindIntervalAccessibilityValue: String {
        let label = AppSettings.skipIntervalLabel(settings.rewindSeconds)
        if settings.rewindSeconds == AppSettings.defaultRewindSeconds {
            return String(
                format: String(localized: "%@. This is the default rewind interval. The next rewind in the mini player, full player, Lockscreen and Now Playing, Siri skip back, and the antennapod skip-back link uses this many seconds. Siri and the link skip only when an episode is already loaded and do not invent one. Changing this updates those controls and does not seek the current position, start playback, or download. It is not Rewind after pause."),
                label
            )
        }
        return String(
            format: String(localized: "%@. This is not the default rewind interval of 10 seconds. The next rewind in the mini player, full player, Lockscreen and Now Playing, Siri skip back, and the antennapod skip-back link uses this many seconds. Siri and the link skip only when an episode is already loaded and do not invent one. Changing this updates those controls and does not seek the current position, start playback, or download. It is not Rewind after pause."),
            label
        )
    }

    private var rewindIntervalAccessibilityHint: String {
        String(localized: "Presets are 5, 10, 15, 20, 30, and 60 seconds, plus Custom from 5 to 60. The default rewind is 10 seconds. The next rewind uses the saved interval. Changing it does not move the current position. Not Rewind after pause, which seeks back only after a pause of at least 1 second.")
    }

    /// VoiceOver for Settings → Fast-forward. Names the saved interval and whether it is
    /// the 30-second default. Changing the picker does not seek.
    private var fastForwardIntervalAccessibilityValue: String {
        let label = AppSettings.skipIntervalLabel(settings.fastForwardSeconds)
        if settings.fastForwardSeconds == AppSettings.defaultFastForwardSeconds {
            return String(
                format: String(localized: "%@. This is the default fast-forward interval. The next fast-forward in the mini player, full player, Lockscreen and Now Playing, Siri skip forward, and the antennapod skip-forward link uses this many seconds. Siri and the link skip only when an episode is already loaded and do not invent one. Changing this updates those controls and does not seek the current position, start playback, or download. It is not Rewind after pause."),
                label
            )
        }
        return String(
            format: String(localized: "%@. This is not the default fast-forward interval of 30 seconds. The next fast-forward in the mini player, full player, Lockscreen and Now Playing, Siri skip forward, and the antennapod skip-forward link uses this many seconds. Siri and the link skip only when an episode is already loaded and do not invent one. Changing this updates those controls and does not seek the current position, start playback, or download. It is not Rewind after pause."),
            label
        )
    }

    private var fastForwardIntervalAccessibilityHint: String {
        String(localized: "Presets are 5, 10, 15, 20, 30, and 60 seconds, plus Custom from 5 to 60. The default fast-forward is 30 seconds. The next fast-forward uses the saved interval. Changing it does not move the current position. Not Rewind after pause.")
    }

    /// VoiceOver for Settings → Rewind after pause. Names the saved preset and whether
    /// it is the 2-second default. Changing the picker does not seek now.
    private var rewindAfterPauseAccessibilityValue: String {
        let seconds = settings.rewindAfterPauseSeconds
        let label = AppSettings.rewindAfterPauseLabel(seconds)
        if seconds <= 0 {
            return String(localized: "Off. This is not the default. Resuming the current item does not seek backward, even after a pause of at least 1 second. Cold play, first start from a row, play from beginning, and stop do not rewind. Changing this does not seek the current position, start playback, or download. It is not the Rewind or Fast-forward skip interval, and not Android elapsed-time tiers.")
        }
        let format = seconds == AppSettings.defaultRewindAfterPauseSeconds
            ? String(localized: "%@. This is the default. The next resume of the current item seeks back this many seconds, not before 0, only after a pause of at least 1 second. A shorter pause does not rewind. Play and pause in the mini player, full player, Lockscreen, and Now Playing count. An audio interruption that pauses counts; if the system resumes, the seek happens then, otherwise on the next manual resume. A soundbite that pauses at its end, and a sleep timer that pauses playback, also count. That sleep-timer pause is separate from any fade rewind. Cold play, first start from a row, play from beginning, and stop do not rewind and do not invent a position. Changing this does not seek now, start playback, or download. It is a fixed number of seconds, not the Rewind or Fast-forward skip interval, and not Android elapsed-time tiers.")
            : String(localized: "%@. This is not the default of 2 seconds. The next resume of the current item seeks back this many seconds, not before 0, only after a pause of at least 1 second. A shorter pause does not rewind. Play and pause in the mini player, full player, Lockscreen, and Now Playing count. An audio interruption that pauses counts; if the system resumes, the seek happens then, otherwise on the next manual resume. A soundbite that pauses at its end, and a sleep timer that pauses playback, also count. That sleep-timer pause is separate from any fade rewind. Cold play, first start from a row, play from beginning, and stop do not rewind and do not invent a position. Changing this does not seek now, start playback, or download. It is a fixed number of seconds, not the Rewind or Fast-forward skip interval, and not Android elapsed-time tiers.")
        return String(format: format, label)
    }

    private var rewindAfterPauseAccessibilityHint: String {
        String(localized: "Presets are Off, 1, 2, 3, 5, and 10 seconds. The default is 2 seconds. Off never seeks on resume. Any other value seeks back that many seconds, not before 0, only when this item resumes after a pause of at least 1 second. Cold play, first start from a row, play from beginning, and stop do not rewind. Changing the picker does not move the current position, start playback, or download. Not the Rewind or Fast-forward buttons, and not Android elapsed-time tiers. There is no Pause-on-headset setting.")
    }


    /// VoiceOver for Settings → Smart mark as played. Off = natural end / explicit mark only.
    /// On = leave/stop within remaining seconds; not near-end scrub; seconds only.
    private var smartMarkAsPlayedAccessibilityValue: String {
        let seconds = settings.smartMarkAsPlayedSeconds
        let label = AppSettings.smartMarkAsPlayedLabel(seconds)
        if seconds <= 0 {
            return String(localized: "Off. This is not the default. Leaving or stopping never smart-marks. Only a natural end or an explicit Mark played counts. Near-end scrub alone does not mark played. Changing this does not mark the loaded episode, seek, start playback, or download. It is seconds remaining only, not a percent threshold, and not Skip outro.")
        }
        let isDefault = seconds == AppSettings.defaultSmartMarkAsPlayedSeconds
        let isPreset = AppSettings.smartMarkAsPlayedPresets.contains(seconds)
        let headFormat: String
        if isDefault {
            headFormat = String(localized: "%@. This is the default.")
        } else if isPreset {
            headFormat = String(localized: "%@. This is not the default of 30 seconds.")
        } else {
            headFormat = String(localized: "%@. This is a custom threshold, not one of the presets, and not the default of 30 seconds.")
        }
        let head = String(format: headFormat, locale: .current, label)
        return head + " " + String(localized: "When you leave or stop the loaded episode with this many seconds or fewer remaining, it is marked played and may leave the queue. Natural end still marks played. Near-end scrub alone does not. Mark unplayed on the loaded episode inside this window stays unplayed for this session until you play to the end. Changing this does not mark the loaded episode now, seek, start playback, or download. Seconds remaining only — not a percent threshold, not Skip outro, and not Reset position when marked played.")
    }

    private var smartMarkAsPlayedAccessibilityHint: String {
        String(localized: "Presets are Off, 15, 30, 60, 120, 300, and 600 seconds, plus Custom from 1 to 600. The default is 30 seconds. Off marks only on natural end or explicit Mark played. Any other value smart-marks on leave or stop within that remaining window. Near-end scrub alone does not mark played. Changing the picker does not mark an episode now. Not Skip outro or Rewind after pause.")
    }

    /// VoiceOver for Settings → Reset position when marked played.
    /// On clears saved position to 0 on mark played; Off keeps it for Mark unplayed resume.
    private var resetPositionWhenMarkedPlayedAccessibilityValue: String {
        if settings.resetPositionWhenMarkedPlayed {
            return String(localized: "On. This is the default. When an episode is marked played — manually, by Mark all, by smart mark on leave or stop, or at natural end — its saved playback position is cleared to 0 so a later Mark unplayed starts from the beginning. Changing this does not seek the loaded episode now, start playback, download, or mark played. It is not Smart mark as played, Continuous playback, or Rewind after pause.")
        }
        return String(localized: "Off. This is not the default. When an episode is marked played — manually, by Mark all, by smart mark on leave or stop, or at natural end — the saved playback position is kept so Mark unplayed can resume there. Changing this does not seek the loaded episode now, start playback, download, or mark played. It is not Smart mark as played, Continuous playback, or Rewind after pause.")
    }

    private var resetPositionWhenMarkedPlayedAccessibilityHint: String {
        String(localized: "On clears the saved position to 0 when marked played. Off keeps the position for resume after Mark unplayed. Applies to manual mark, Mark all, smart mark, and natural end. Default on. The switch does not seek now, start playback, or download.")
    }

    /// Spoken preset for Settings Skip intro / Skip outro. The visible picker
    /// still uses `AppSettings.skipIntroOutroLabel`. Off and the preset second counts are catalog-backed.
    private func skipIntroOutroVoiceOverLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            return String(localized: "Off")
        case 5:
            return String(localized: "5 seconds")
        case 10:
            return String(localized: "10 seconds")
        case 15:
            return String(localized: "15 seconds")
        case 30:
            return String(localized: "30 seconds")
        case 60:
            return String(localized: "60 seconds")
        default:
            return AppSettings.skipIntroOutroLabel(seconds)
        }
    }

    /// VoiceOver for Settings → Skip intro. Off is the default. A fresh start
    /// (saved position at most about 1 second, not play from beginning) seeks once.
    /// Changing the picker does not seek now. A per-podcast override wins.
    private var skipIntroAccessibilityValue: String {
        let seconds = settings.skipIntroSeconds
        if seconds <= 0 {
            return String(localized: "Off. This is the default. A fresh start stays at the beginning and does not seek forward. Play from beginning stays at 0. Resume when the saved position is past about 1 second does not skip an intro. A played episode whose resume position is 0 is a fresh start. Changing this does not seek now, start playback, or download. A per-podcast Skip intro override still replaces this global value. It is not Rewind, Fast-forward, Skip outro, Skip silence, or Rewind after pause.")
        }
        return String(
            format: String(localized: "%@. This is not the default of Off. The next fresh start seeks forward once to this many seconds when the saved position is at most about 1 second. Play from beginning stays at 0 and does not skip the intro. Resume past about 1 second does not skip the intro. A played episode whose resume position is 0 counts as a fresh start. Changing this does not seek now, start playback, or download. A per-podcast override replaces this global value. It is not the Rewind or Fast-forward skip interval, Skip outro, Skip silence, or Rewind after pause."),
            skipIntroOutroVoiceOverLabel(seconds)
        )
    }

    private var skipIntroAccessibilityHint: String {
        String(localized: "Presets are Off, 5, 10, 15, 30, and 60 seconds. The default is Off. Off never seeks on a fresh start. Any other value seeks forward once to that many seconds only when the saved position is about 0. Play from beginning does not skip the intro. Resuming past about 1 second does not skip the intro. Changing the picker does not seek now, start playback, or download. Feed detail can override this for one podcast. Not Rewind, Fast-forward, Skip outro, Skip silence, or Rewind after pause.")
    }

    /// VoiceOver for Settings → Skip outro. Off is the default. A non-zero value
    /// finishes once per session like a natural end when duration is known.
    /// Changing the picker does not mark played now. A per-podcast override wins.
    private var skipOutroAccessibilityValue: String {
        let seconds = settings.skipOutroSeconds
        if seconds <= 0 {
            return String(localized: "Off. This is the default. Playback does not finish early while time remains. Unknown duration does not invent an end. Changing this does not mark the current episode played, seek, start playback, or download. A per-podcast Skip outro override still replaces this global value. It is not Smart mark as played, Skip intro, Skip silence, or Rewind after pause.")
        }
        return String(
            format: String(localized: "%@. This is not the default of Off. While this episode is playing, if duration is known, position is past 1 second, and remaining time is at most this many seconds, it finishes once this session the same way as a natural end: mark played, then Continuous playback decides what plays next. Off stops. Queue plays the next queue item only. Same podcast plays the next unplayed, non-archived episode of this podcast only. An end-of-episode or end-of-chapter sleep timer still stops without advancing. End of queue still advances only through the queue. It does not fire at the very start. Unknown duration does not finish early. Changing this does not mark played now, seek, start playback, or download. A per-podcast override replaces this global value. It is not Smart mark as played, which applies when leaving or stopping, and not Skip intro, Skip silence, or Rewind after pause."),
            skipIntroOutroVoiceOverLabel(seconds)
        )
    }

    private var skipOutroAccessibilityHint: String {
        String(localized: "Presets are Off, 5, 10, 15, 30, and 60 seconds. The default is Off. Off never finishes early. Any other value finishes once per play session when remaining time is within that window, duration is known, and playback is past 1 second, the same as a natural end. Continuous playback chooses what plays next. Changing the picker does not mark played now, seek, start playback, or download. Feed detail can override this for one podcast. Not Smart mark as played, Skip intro, Skip silence, or Rewind after pause.")
    }

    /// VoiceOver for Settings → Show remaining time. Off is the default and
    /// keeps total duration on the mini and full player right label. On shows
    /// −remaining there. List/Home bars, chapter remaining, Lock Screen,
    /// Now Playing, widget, and Watch are not this switch.
    private var showRemainingTimeAccessibilityValue: String {
        if settings.showRemainingTime {
            return String(localized: "On. This is not the default. The mini player and the full player show remaining time on the right instead of total duration: duration minus position, with a leading minus. The left side stays the current position. Tapping the full-player right time label toggles this same setting. If duration is unknown, no remaining time and no total duration are invented. List and Home remaining-time bars already show remaining time and are not turned on by this switch. Chapter remaining is separate and stays as it is. When Remaining time respects speed is also on, this player remaining time uses the live session rate, or the podcast or default speed if there is no live rate, clamped from 0.5 to 3.0. When that setting is off, this label stays wall-clock. Lock Screen and Now Playing keep elapsed time and playback duration. The widget and Watch stay wall-clock. Turning this on does not start playback, seek, change the playback rate, or download.")
        }
        return String(localized: "Off. This is the default. The mini player and the full player show total duration on the right. The left side stays the current position. If duration is unknown, no total duration is invented. List and Home remaining-time bars still show remaining time; this switch does not turn those bars off. Chapter remaining is unchanged. Lock Screen, Now Playing, the widget, and Watch do not switch to a minus-remaining label. Turning this off does not start playback, seek, change the playback rate, or download.")
    }

    private var showRemainingTimeAccessibilityHint: String {
        String(localized: "Off is the default and shows total duration on the right of the mini player and the full player. On shows remaining time there instead, duration minus position, with a leading minus. The left side stays the current position. Tapping the full-player right time label toggles the same setting. Unknown duration invents neither a remaining time nor a total duration. List and Home remaining-time bars, chapter remaining, Lock Screen, Now Playing, the widget, and Watch are not changed by this switch. The player remaining label is divided by speed only when Remaining time respects speed is also on; otherwise it is wall-clock. The switch does not start playback, seek, change the playback rate, or download.")
    }

    /// VoiceOver for Settings → Remaining time respects speed. Off is the default
    /// and keeps wall-clock remaining. On divides list/Home bars by feed or
    /// default speed (≥ 0.5), not the live session rate. Player −remaining
    /// (only when Show remaining time is on) and current-chapter remaining use
    /// the live session rate, clamped 0.5…3.0.
    private var remainingTimeRespectsSpeedAccessibilityValue: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "On. This is not the default. List and Home remaining-time bars divide each episode’s remaining by that podcast’s playback speed: the per-podcast speed if one is set, otherwise Default speed, and never below 0.5. It is an estimate, not a live ETA, and those bars do not use the current player session rate. Unknown durations stay marked with a tilde, and a played episode that is not the current one still counts as zero remaining. Mini and full player remaining time, only when Show remaining time is also on, and the current chapter’s remaining, use the live session rate, or the podcast or default speed if there is no live rate, clamped from 0.5 to 3.0. Chapter duration labels stay wall-clock. Sleep-timer end of chapter stays wall-clock. Volume boost is not speed. Widget and Watch Continue, Lock Screen, and Now Playing stay wall-clock. Turning this on does not start playback, seek, change the playback rate, or download, and it does not invent a duration.")
        }
        return String(localized: "Off. This is the default. List and Home remaining-time bars, mini and full player remaining time, and chapter remaining stay wall-clock. No speed-adjusted time is invented. Unknown durations stay marked with a tilde, and a played episode that is not the current one still counts as zero remaining. Widget and Watch Continue, Lock Screen, and Now Playing stay wall-clock either way. Turning this off does not start playback, seek, change the playback rate, or download.")
    }

    private var remainingTimeRespectsSpeedAccessibilityHint: String {
        String(localized: "Off is the default and keeps remaining time as wall-clock. On divides list and Home remaining by each podcast’s speed, the per-podcast override or Default speed, at least 0.5, as an estimate and not the live session rate. Mini and full remaining, when Show remaining time is on, and the current chapter’s remaining use the live session rate, clamped from 0.5 to 3.0. Chapter durations, sleep-timer end of chapter, the widget, Watch, Lock Screen, and Now Playing stay wall-clock. Volume boost is not speed. The switch does not start playback, seek, change the playback rate, or download, and it does not invent a duration.")
    }

    /// VoiceOver for Settings → Volume boost. 100% is unity (no soft gain).
    /// Above 100% is software gain on the audio mix and may clip. Changing the
    /// picker applies only when a loaded item's audio tracks can be read.
    /// It does not change playback speed.
    /// VoiceOver for Settings → Volume adaptation. On is AVAudioSession spokenAudio
    /// (voiceChat fallback) — a session mode, not gain / LoudnessEnhancer / Volume boost.
    private var volumeAdaptationAccessibilityValue: String {
        if settings.volumeAdaptationEnabled {
            return String(localized: "On. This is not the default. The audio session uses spoken-audio mode for speech, or voice-chat if spoken-audio is refused. It does not raise loudness, apply ReplayGain, or change Volume boost. When an episode is paused, changing this does not activate the session or interrupt other apps; it applies on the next play. Video with a visible surface still uses movie playback when this is off. Not Volume boost, Skip silence, or Preserve pitch.")
        }
        return String(localized: "Off. This is the default. Audio uses the default session mode, and video with a visible surface uses movie playback. Turning this off does not change Volume boost, start playback, seek, or download. Not Android LoudnessEnhancer.")
    }

    private var volumeAdaptationAccessibilityHint: String {
        String(localized: "On sets a speech-oriented audio session mode. Off uses default or movie playback. This is not loudness gain, Volume boost, Skip silence, or Preserve pitch. Default off. The switch does not start playback or download.")
    }

    private var volumeBoostAccessibilityValue: String {
        let percent = AppSettings.clampVolumeBoostPercent(settings.volumeBoostPercent)
        let label = AppSettings.volumeBoostLabel(percent)
        if percent <= AppSettings.defaultVolumeBoostPercent {
            return String(
                format: String(localized: "%@. This is the default. No soft gain is applied, and the audio mix stays at unity. If an episode is already loaded, this clears that mix on the current item. If nothing is loaded, it is saved for the next one. Above 100% would be software gain and may clip or distort. This does not start playback, seek, change playback speed, or download. Sleep-timer fade still uses player volume and is separate. Not Volume adaptation, ReplayGain, loudness normalization, Android LoudnessEnhancer, or an audio engine. Some streams, including HLS, may ignore the audio mix. If the item has no audio tracks, or the tracks cannot be read, no boost is invented. Stock AVPlayer keeps video, Picture in Picture, and Now Playing."),
                label
            )
        }
        return String(
            format: String(localized: "%@. This is not the default of 100%. Soft gain is software volume on the audio mix, using this percent divided by 100, and it may clip or distort. If an episode is already loaded and its audio tracks can be read, this applies to that item. If nothing is loaded, or there are no audio tracks, or the tracks cannot be read, nothing is boosted and no louder result is invented. This does not start playback, seek, change playback speed, or download. Sleep-timer fade still uses player volume and multiplies with the mix. Not Volume adaptation, ReplayGain, loudness normalization, Android LoudnessEnhancer, or an audio engine. Some streams, including HLS, may ignore the audio mix, so the boost then has no effect. Stock AVPlayer keeps video, Picture in Picture, and Now Playing."),
            label
        )
    }

    private var volumeBoostAccessibilityHint: String {
        String(localized: "Presets are 100%, 125%, 150%, 175%, 200%, 250%, and 300%. There is no custom percent. The default is 100%, which is unity and clears the audio mix. Above 100% is soft gain and may clip or distort. Changing this applies to a loaded item only when its audio tracks can be read; otherwise it is saved and no boost is invented. It does not start playback, seek, change playback speed, or download. Not Volume adaptation, Preserve pitch, Skip silence, ReplayGain, or LoudnessEnhancer. Sleep-timer fade stays on player volume.")
    }

    /// VoiceOver for Settings → Default speed. 1.0× is the default.
    /// A different episode (or the next play after Stop) uses this unless that
    /// podcast has its own speed. The loaded item keeps its session rate.
    /// Changing the picker persists the preference and does not call setRate.
    private var defaultSpeedAccessibilityValue: String {
        let label = PlaybackService.formatPlaybackSpeed(settings.defaultPlaybackSpeed)
        let speed = settings.defaultPlaybackSpeed
        let isDefault = abs(speed - 1.0) < 0.001
        let isPreset = AppSettings.speedPresets.contains(speed)
        let headFormat: String
        if isDefault {
            headFormat = String(localized: "%@. This is the default.")
        } else if isPreset {
            headFormat = String(localized: "%@. This is not the default of 1.0×.")
        } else {
            headFormat = String(localized: "%@. This is a custom speed, not one of the presets, and not the default of 1.0×.")
        }
        let head = String(format: headFormat, locale: .current, label)
        return head + " " + String(localized: "A different episode starts at this speed unless that podcast has its own playback speed. An episode with no podcast uses this speed. The episode already loaded keeps its session rate, including when you play that same episode again without stopping. After Stop, the next play is a fresh start and uses this speed unless a podcast override applies. Changing this does not change the rate already playing, start playback, seek, or download. List and Home remaining-time bars use this speed only when Remaining time respects speed is on and that podcast has no speed override. Those bars are not the live session rate. Mini and full player remaining time uses the live session rate while one is set. Not Volume boost, Preserve pitch, or Skip silence. Stock AVPlayer, not Android ExoPlayer. Quality may be worse above about 2×.")
    }

    private var defaultSpeedAccessibilityHint: String {
        String(localized: "Presets are 0.8×, 1.0×, 1.1×, 1.2×, 1.3×, 1.5×, and 2.0×, plus Custom from 0.50× to 3.00× in steps of 0.05. The default is 1.0×. A podcast playback-speed override replaces this for that podcast and, unlike this picker, also changes the rate if an episode from that podcast is already loaded. Changing this picker does not change the rate already playing, start playback, seek, or download. Player tap and long-press change only the session rate unless Also set as default is on. Not Volume boost, Preserve pitch, or Skip silence.")
    }

    private var refreshHelpText: String {
        if settings.refreshInterval == .manual {
            return String(localized: "Feeds refresh when you pull to refresh (Subscriptions, Home, or Inbox), use Refresh all, or refresh a podcast alone. Bulk refresh skips Keep updated Never; swipe or Feed detail refresh still works for those podcasts. Background App Refresh is not enabled in this beta (Info.plist has no fetch mode).")
        }
        return String(localized: "When you open the app (launch or return to foreground), subscriptions refresh if this interval has elapsed, except podcasts set to Keep updated Never. Same bulk path as Refresh all and pull-to-refresh. Manual single-podcast refresh still works for Never feeds. Background App Refresh is stubbed until Info.plist adds fetch.")
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
        String(localized: "Pull to refresh on Subscriptions, Home, or Inbox, or use Refresh all — Keep updated Never podcasts are skipped. A timed interval also checks when you open the app. iOS Background App Refresh is not enabled in this beta.")
    }

    /// VoiceOver for Settings → Refresh interval. Timed checks run on launch/foreground only —
    /// not iOS Background App Refresh. Keep updated Never skips bulk paths.
    private var refreshIntervalAccessibilityValue: String {
        let label = settings.refreshInterval.label
        switch settings.refreshInterval {
        case .manual:
            return String(localized: "Manual only. This is the default. Subscriptions refresh when you pull to refresh on Subscriptions, Home, or Inbox, use Refresh all, or refresh one podcast. There is no timed check when you open the app. Keep updated Never podcasts are skipped on Refresh all and pull-to-refresh; a single-podcast refresh still works. iOS Background App Refresh is not enabled in this beta. Changing this does not refresh now, download, or invent new episodes.")
        case .oneHour, .fourHours, .twelveHours, .twentyFourHours:
            let head = String(format: String(localized: "%@. This is not the default of Manual only."), locale: .current, label)
            return head + " " + String(localized: "When you open the app or return to the foreground, subscriptions refresh if this interval has elapsed since the last bulk refresh finished. Same bulk path as Refresh all and pull-to-refresh. Keep updated Never podcasts are skipped on those bulk paths; a single-podcast refresh still works. This is not iOS Background App Refresh — nothing runs while the app is fully quit. Changing this does not refresh now, download, or invent new episodes.")
        }
    }

    private var refreshIntervalAccessibilityHint: String {
        String(localized: "Choices are Manual only, Every 1 hour, Every 4 hours, Every 12 hours, and Every 24 hours. The default is Manual only. Timed intervals check only when you open the app or return to the foreground — not as iOS Background App Refresh. Keep updated Never skips Refresh all, pull-to-refresh, and timed refresh; single-podcast refresh still works. Changing the picker does not refresh now.")
    }


    @ViewBuilder
    private var autoDownloadSection: some View {
        Section {
            Toggle("Auto-download", isOn: $settings.autoDownloadEnabled)
                .accessibilityLabel(String(localized: "Auto-download"))
                .accessibilityValue(autoDownloadToggleAccessibilityValue)
                .accessibilityHint(autoDownloadToggleAccessibilityHint)
            if settings.autoDownloadEnabled {
                Picker(String(localized: "Episodes per feed"), selection: $settings.autoDownloadEpisodesPerFeed) {
                    ForEach(AutoDownloadEpisodesPerFeed.allCases) { cap in
                        Text(cap.label).tag(cap)
                    }
                }
                .accessibilityLabel(String(localized: "Episodes per feed"))
                .accessibilityValue(autoDownloadCapAccessibilityValue)
                .accessibilityHint(autoDownloadCapAccessibilityHint)
            }
            Text(autoDownloadHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Auto-download help"))
                .accessibilityValue(autoDownloadHelpText)
        } header: {
            Text("Auto-download")
        }
    }

    /// VoiceOver for the global Auto-download switch. Off does not mean every podcast
    /// is skipped: per-podcast Always can still enqueue newly appeared IDs.
    private var autoDownloadToggleAccessibilityValue: String {
        guard settings.autoDownloadEnabled else {
            return String(localized: "Off. This global switch does not enqueue episodes. A per-podcast Always override can still enqueue newly appeared episodes for that podcast. The unplayed backlog is not downloaded, and no download is invented.")
        }
        return String(localized: "On. After a successful feed refresh, up to \(settings.autoDownloadEpisodesPerFeed.rawValue) newly appeared unplayed episode(s) per feed may be enqueued. Not the whole unplayed backlog.")
    }

    private var autoDownloadToggleAccessibilityHint: String {
        String(localized: "Only newly appeared episode IDs after a successful refresh are candidates. Local-folder and file feeds are skipped. There is no separate Background App Refresh download. Wi‑Fi-only for auto-download is under Network / Downloads. Per-podcast Never skips that podcast. Manual downloads are unchanged.")
    }

    /// VoiceOver for Episodes per feed. The visible preset stays; the value states the cap is not a backlog download.
    private var autoDownloadCapAccessibilityValue: String {
        String(localized: "\(settings.autoDownloadEpisodesPerFeed.label). This cap counts only newly appeared unplayed episodes after a successful feed refresh, not the unplayed backlog.")
    }

    private var autoDownloadCapAccessibilityHint: String {
        String(localized: "Shown only while global auto-download is on. The same cap applies when a podcast is set to Always. Per-podcast Never still skips that podcast. Does not change the Wi‑Fi-only gate under Network / Downloads. Local-folder feeds are skipped. Not a silent background download.")
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
                Text(currentNetworkStatusLabel)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Current network"))
            .accessibilityValue(currentNetworkAccessibilityValue)
            .accessibilityHint(String(localized: "After the first path sample, Wi‑Fi and Ethernet allow Wi‑Fi-only actions; cellular, other, and offline do not. Before that sample the row says Checking and does not claim Wi‑Fi. No VPN or proxy detection. Feed refresh is not a Wi‑Fi-only action and may use cellular."))

            Toggle(String(localized: "Auto-download Wi‑Fi only"), isOn: gatedWifiToggle(\AppSettings.autoDownloadWifiOnly))
                .accessibilityLabel(String(localized: "Auto-download Wi‑Fi only"))
                .accessibilityValue(wifiOnlyToggleAccessibilityValue(isOn: settings.autoDownloadWifiOnly, role: .autoDownload))
                .accessibilityHint(String(localized: "When on (default), auto-download after refresh skips cellular. Does not block manual downloads."))
                .onChange(of: settings.autoDownloadWifiOnly) { _, _ in
                    downloads.pumpWaitingQueue()
                }
            Toggle(String(localized: "Manual download Wi‑Fi only"), isOn: gatedWifiToggle(\AppSettings.manualDownloadWifiOnly))
                .accessibilityLabel(String(localized: "Manual download Wi‑Fi only"))
                .accessibilityValue(wifiOnlyToggleAccessibilityValue(isOn: settings.manualDownloadWifiOnly, role: .manualDownload))
                .accessibilityHint(String(localized: "When on, user-initiated downloads are refused on cellular and an error is recorded. Default off — manual downloads may use mobile data."))
            Toggle(String(localized: "Stream Wi‑Fi only"), isOn: gatedWifiToggle(\AppSettings.streamWifiOnly))
                .accessibilityLabel(String(localized: "Stream Wi‑Fi only"))
                .accessibilityValue(wifiOnlyToggleAccessibilityValue(isOn: settings.streamWifiOnly, role: .stream))
                .accessibilityHint(String(localized: "When on, network streaming is blocked on cellular; local offline files still play. Default off."))
            if parental.isEnabled && parental.lockNetworkDownloadsSettings && parental.isLocked {
                Text(String(localized: "Network / Downloads settings are locked. Enter the parental PIN to change these toggles."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            TextField(
                String(localized: "Custom User-Agent"),
                text: $customUserAgentDraft,
                prompt: Text(AppUserAgent.defaultValue)
            )
            .onChange(of: customUserAgentDraft) { _, newValue in
                settings.customUserAgent = newValue
            }
            .onChange(of: settings.customUserAgent) { _, stored in
                // Restore or Reset changed the saved value; show it unless it is what is being typed.
                if AppUserAgent.sanitize(customUserAgentDraft) != stored {
                    customUserAgentDraft = stored
                }
            }
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
                    text: $httpProxyUsernameDraft,
                    prompt: Text(String(localized: "Optional"))
                )
                .onChange(of: httpProxyUsernameDraft) { _, newValue in
                    settings.httpProxyUsername = newValue
                }
                .onChange(of: settings.httpProxyUsername) { _, stored in
                    if AppHTTPProxy.sanitizeUsername(httpProxyUsernameDraft) != stored {
                        httpProxyUsernameDraft = stored
                    }
                }
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
            customUserAgentDraft = settings.customUserAgent
            httpProxyUsernameDraft = settings.httpProxyUsername
        }
        .sheet(isPresented: $showNetworkPINGate) {
            ParentalPINPromptSheet(
                title: String(localized: "Parental controls"),
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

    /// Visible Current network label. The gate's optimistic `.wifi` default is not shown.
    private var currentNetworkStatusLabel: String {
        guard networkPath.hasReportedPath else {
            return String(localized: "Checking…")
        }
        return networkPath.kind.statusLabel
    }

    /// VoiceOver for Current network. Checking is not a measured Wi‑Fi path.
    private var currentNetworkAccessibilityValue: String {
        guard networkPath.hasReportedPath else {
            return String(localized: "Checking. The system path monitor has not delivered a sample, so this is not Wi‑Fi, Ethernet, cellular, offline, or another network. No status is invented.")
        }
        return networkPath.kind.statusLabel
    }

    private enum WifiOnlyVoiceOverRole {
        case autoDownload
        case manualDownload
        case stream
    }

    /// VoiceOver value for a Wi‑Fi-only toggle: saved On/Off, what that action does, and the
    /// reported path. A missing sample is not spoken as allowed or blocked.
    private func wifiOnlyToggleAccessibilityValue(isOn: Bool, role: WifiOnlyVoiceOverRole) -> String {
        var parts: [String] = []
        if parental.needsPINForNetworkDownloads {
            parts.append(String(localized: "Locked. Enter the parental PIN to change this toggle. The saved On or Off choice stays until then."))
        }
        parts.append(isOn ? String(localized: "On.") : String(localized: "Off."))
        parts.append(wifiOnlyPolicySentence(isOn: isOn, role: role))
        parts.append(wifiOnlyPathSentence)
        return parts.joined(separator: " ")
    }

    private func wifiOnlyPolicySentence(isOn: Bool, role: WifiOnlyVoiceOverRole) -> String {
        switch (role, isOn) {
        case (.autoDownload, true):
            return String(localized: "Auto-download after a successful refresh is skipped unless the path is Wi‑Fi or Ethernet. This does not start a download. Manual downloads and streaming stay on their own toggles. Feed refresh itself is not blocked and may still use cellular.")
        case (.autoDownload, false):
            return String(localized: "Auto-download is not limited to Wi‑Fi or Ethernet. It still runs only after a successful refresh and still needs a satisfied path. This does not start a download. Feed refresh is also not limited by this toggle.")
        case (.manualDownload, true):
            return String(localized: "User-started downloads are refused unless the path is Wi‑Fi or Ethernet, and a download error is recorded. Files already saved stay. This does not start a download.")
        case (.manualDownload, false):
            return String(localized: "User-started downloads are not limited to Wi‑Fi or Ethernet by this toggle. A missing network can still fail the transfer. No Wi‑Fi-only error is recorded just because this is off.")
        case (.stream, true):
            return String(localized: "Network streaming is blocked unless the path is Wi‑Fi or Ethernet. Local offline files still play. This does not download the episode.")
        case (.stream, false):
            return String(localized: "Network streaming is not limited to Wi‑Fi or Ethernet by this toggle. Local offline files still play. This does not download the episode.")
        }
    }

    /// Describes the measured path only. Does not claim the toggle allows or blocks it.
    private var wifiOnlyPathSentence: String {
        guard networkPath.hasReportedPath else {
            return String(localized: "Current network is not yet reported. It is not assumed to be Wi‑Fi, and this row does not claim the action is allowed or blocked.")
        }
        switch networkPath.kind {
        case .wifi:
            return String(localized: "Reported network is Wi‑Fi.")
        case .ethernet:
            return String(localized: "Reported network is Ethernet.")
        case .cellular:
            return String(localized: "Reported network is Cellular.")
        case .other:
            return String(localized: "Reported network is another interface, not Wi‑Fi.")
        case .offline:
            return String(localized: "Reported network is offline. No network is invented.")
        }
    }

    private var networkDownloadsHelpText: String {
        String(localized: "Wi‑Fi / Ethernet vs cellular (system path monitor — no VPN or proxy detection). Auto-download Wi‑Fi only defaults on — skips auto enqueue on cellular. Manual downloads allow cellular by default; Manual download Wi‑Fi only refuses user-initiated downloads on cellular and records an error. Stream Wi‑Fi only (default off) blocks network stream URLs on cellular; local offline files still play. Turn a toggle off to allow cellular for that action. Feed refresh (Refresh all, pull-to-refresh, timed interval, and single-podcast refresh) is not limited by these toggles and may use cellular — there is no separate Mobile updates setting.")
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
                .accessibilityValue(notificationToggleAccessibilityValue(isOn: settings.notifyOnNewEpisodes, role: .newEpisodes))
                .accessibilityHint(String(localized: "Master switch for local new-episode notifications after refresh. Per-podcast Off silences that feed; per-podcast On is ignored while this is off. No push server."))
            Toggle("Notify on download errors", isOn: $settings.notifyOnDownloadErrors)
                .accessibilityValue(notificationToggleAccessibilityValue(isOn: settings.notifyOnDownloadErrors, role: .downloadErrors))
                .accessibilityHint(String(localized: "Local notifications when a download fails — not when a download completes successfully."))
            Toggle("Notify on download complete", isOn: $settings.notifyOnDownloadComplete)
                .accessibilityValue(notificationToggleAccessibilityValue(isOn: settings.notifyOnDownloadComplete, role: .downloadComplete))
                .accessibilityHint(String(localized: "Optional local notifications when a download finishes successfully. Default off — quieter than download errors."))
            Toggle("Notify on sync errors", isOn: $settings.notifyOnSyncErrors)
                .accessibilityValue(notificationToggleAccessibilityValue(isOn: settings.notifyOnSyncErrors, role: .syncErrors))
                .accessibilityHint(String(localized: "Local notifications when gpodder or Nextcloud sync fails."))
            Toggle("Notify when sleep timer ends", isOn: $settings.notifyOnSleepTimerEnd)
                .accessibilityValue(notificationToggleAccessibilityValue(isOn: settings.notifyOnSleepTimerEnd, role: .sleepTimer))
                .accessibilityHint(String(localized: "Local notification and haptic when the sleep timer pauses or stops playback. Banner tap opens no screen."))

            LabeledContent("Permission") {
                Text(notificationAuthStatus.label)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Permission"))
            .accessibilityValue(notificationPermissionAccessibilityValue)
            .accessibilityHint(String(localized: "Rechecked when Settings appears and when AntennaPod becomes active. Open iOS Settings is shown only when permission is Denied."))

            if notificationAuthStatus == .denied {
                Button("Open iOS Settings") {
                    NewEpisodeNotificationCoordinator.openSystemNotificationSettings()
                }
                .accessibilityHint(String(localized: "Opens the system Settings app so you can allow Notifications for AntennaPod. App toggles stay on; banners stay off until iOS allows them."))
            }

            LabeledContent("Notifies") {
                Text(String(localized: "New episodes after refresh (one local banner → Inbox; title podcast or New episode(s); body episode title or count); download failures → Downloads (title episode, or podcast if episode title empty); download complete (optional, default off) → Downloads (title episode, or podcast if episode title empty); sync/login failures → Settings Sync (banner title Login failed, Not logged in, or Sync failed); sleep timer end (banner + foreground haptic; tap opens no screen)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Notifies"))
            .accessibilityValue(String(localized: "New episodes after refresh (one local banner → Inbox; title podcast or New episode(s); body episode title or count); download failures → Downloads (title episode, or podcast if episode title empty); download complete (optional, default off) → Downloads (title episode, or podcast if episode title empty); sync/login failures → Settings Sync (banner title Login failed, Not logged in, or Sync failed); sleep timer end (banner + foreground haptic; tap opens no screen)"))

            LabeledContent("Does not notify") {
                Text(String(localized: "No push / APNs / server-side alerts. Download-complete banners only when that optional toggle is on (default off). No episode-level deep link for new episodes (Inbox only). Sleep timer banner tap opens no screen. Needs an in-app refresh, download, sync, or sleep-timer fire — not a remote push."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Does not notify"))
            .accessibilityValue(String(localized: "No push / APNs / server-side alerts. Download-complete banners only when that optional toggle is on (default off). No episode-level deep link for new episodes (Inbox only). Sleep timer banner tap opens no screen. Needs an in-app refresh, download, sync, or sleep-timer fire — not a remote push."))

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

    /// VoiceOver for a notification toggle. On/Off is the saved preference only.
    /// The permission clause is the last read status — Checking does not claim a banner.
    private func notificationToggleAccessibilityValue(isOn: Bool, role: NotificationVoiceOverRole) -> String {
        [
            isOn ? String(localized: "On.") : String(localized: "Off."),
            notificationPolicySentence(isOn: isOn, role: role),
            notificationPermissionClause,
        ].joined(separator: " ")
    }

    private func notificationPolicySentence(isOn: Bool, role: NotificationVoiceOverRole) -> String {
        switch (role, isOn) {
        case (.newEpisodes, true):
            return String(localized: "After a successful refresh, one local banner may open Inbox for newly appeared episodes. Title is the podcast name, or New episode / New episodes when the podcast title is empty. Body is the episode title when a single new episode has a title; otherwise a singular or plural count. A per-podcast Off still silences that feed. This toggle does not post a banner by itself and does not download episodes.")
        case (.newEpisodes, false):
            return String(localized: "New-episode banners stay off for every podcast. A per-podcast On does not override this. This does not post a banner and does not change downloads.")
        case (.downloadErrors, true):
            return String(localized: "When a download fails, one local banner may open Downloads. Title is the episode title, or the podcast title when the episode title is empty, or Download failed. Body is a short error. Successful downloads use the separate download-complete toggle. This toggle does not post a banner by itself.")
        case (.downloadErrors, false):
            return String(localized: "Download-failure banners stay off. Failures can still appear in Download errors. Successful downloads are unchanged. This does not post a banner.")
        case (.downloadComplete, true):
            return String(localized: "When a download finishes and the file is saved, one local banner may open Downloads. Title is the episode title, or the podcast title when the episode title is empty, or Download complete. Body is the podcast title when the episode title is present, otherwise Download complete. Cancelled and failed downloads are not included. This toggle does not post a banner by itself.")
        case (.downloadComplete, false):
            return String(localized: "Successful-download banners stay off. Failures stay on their own toggle. This does not post a banner.")
        case (.syncErrors, true):
            return String(localized: "When gpodder or Nextcloud login or sync fails, one local banner may open Settings Sync. Banner title is Login failed, Not logged in, or Sync failed — not always Sync failed for login. This toggle does not post a banner by itself and does not start a sync.")
        case (.syncErrors, false):
            return String(localized: "Sync and login failure banners stay off. This does not post a banner and does not start a sync.")
        case (.sleepTimer, true):
            return String(localized: "When the sleep timer pauses or stops playback, a foreground haptic may play if AntennaPod is active, and a local banner may be posted only if iOS permission allows banners. Banner tap opens no screen — not Inbox, Downloads, or Settings. This toggle does not start or end a timer.")
        case (.sleepTimer, false):
            return String(localized: "Sleep-timer banners and the foreground haptic stay off. The timer itself is unchanged. This toggle does not start or end a timer.")
        }
    }

    /// Spoken with each toggle. Does not treat an unread status as Allowed.
    private var notificationPermissionClause: String {
        switch notificationAuthStatus {
        case .checking:
            return String(localized: "iOS notification permission is still being checked. This is not Allowed, Denied, Not determined, Temporary, or Unknown, and this toggle does not claim a banner will appear.")
        case .allowed:
            return String(localized: "iOS notification permission is Allowed. A local banner can be posted when this toggle is on and the event happens. Not a push or APNs grant.")
        case .denied:
            return String(localized: "iOS notification permission is Denied. The saved On or Off choice stays, but no local banner is posted until Notifications are allowed in iOS Settings.")
        case .notDetermined:
            return String(localized: "iOS notification permission is Not determined. Turning this on asks iOS for permission. This toggle does not post a banner by itself.")
        case .unknown:
            return String(localized: "iOS notification permission is Unknown. This toggle does not claim a banner will appear.")
        case .ephemeral:
            return String(localized: "iOS notification permission is Temporary. This beta posts local banners only for authorized or provisional, so no banner is posted.")
        }
    }

    /// Permission row. Ephemeral is not labeled Allowed: banners are not posted for it.
    private var notificationPermissionAccessibilityValue: String {
        switch notificationAuthStatus {
        case .checking:
            return String(localized: "Checking. iOS notification authorization has not been read yet, so this is not Allowed, Denied, Not determined, Temporary, or Unknown. No permission is invented. Local UserNotifications only — no push or APNs.")
        case .allowed:
            return String(localized: "Allowed. Local banners can be posted when a notification toggle is on and an event happens. This is not a push or APNs grant.")
        case .denied:
            return String(localized: "Denied. Saved On or Off choices stay, but local banners stay off until Notifications are allowed in iOS Settings. No push or APNs.")
        case .notDetermined:
            return String(localized: "Not determined. iOS has not been asked. Turning a notification toggle on asks for permission and does not post a banner by itself. No push or APNs.")
        case .unknown:
            return String(localized: "Unknown. Notification authorization could not be read. This row does not claim banners are allowed or blocked. No push or APNs.")
        case .ephemeral:
            return String(localized: "Temporary. iOS granted ephemeral authorization. This beta posts local banners only for authorized or provisional, so banners stay off. A foreground sleep-timer haptic can still run when that toggle is on. No push or APNs.")
        }
    }

    private var notificationsHelpText: String {
        if notificationAuthStatus == .checking {
            return String(localized: "Notification permission is still being checked. Toggles show the saved choice. This does not claim banners are allowed yet. Local UserNotifications only — no push or APNs.")
        }
        if notificationAuthStatus == .unknown {
            return String(localized: "Notification permission could not be read. This does not claim banners are allowed or blocked. Local UserNotifications only — no push or APNs.")
        }
        if notificationAuthStatus == .ephemeral {
            return String(localized: "iOS reports a temporary (ephemeral) notification authorization. This beta posts local banners only for authorized or provisional, so banners stay off. Toggles stay as saved. A foreground sleep-timer haptic can still run when that toggle is on. No push or APNs.")
        }
        if notificationAuthStatus == .denied {
            return String(localized: "Notification permission was denied. AntennaPod will not show banners until you allow Notifications in iOS Settings (Open iOS Settings). Toggles stay on so your preference is clear. Local UserNotifications only — never push / APNs / server-side alerts. Download-complete is optional (default off).")
        }
        if !settings.notifyOnNewEpisodes && !settings.notifyOnDownloadErrors && !settings.notifyOnDownloadComplete && !settings.notifyOnSyncErrors && !settings.notifyOnSleepTimerEnd {
            return String(localized: "When enabled: new episodes after refresh (one aggregated local banner → Inbox; title podcast or New episode(s); body episode or count), download failures → Downloads, download complete (optional, default off) → Downloads, gpodder/Nextcloud login or sync failures → Settings Sync (banner title Login failed, Not logged in, or Sync failed), and/or sleep timer end (banner + foreground haptic; tap opens no screen). Local only — no push / APNs; iOS Notifications permission required.")
        }
        if notificationAuthStatus == .notDetermined {
            return String(localized: "iOS permission is requested when you turn a notification toggle on, or when a refresh first finds new episodes / a download fails or completes / sync fails / sleep timer ends. Local UserNotifications only — no push / APNs / server-side alerts. Download-complete is optional (default off).")
        }
        var parts: [String] = []
        if settings.notifyOnNewEpisodes {
            parts.append(String(localized: "New episodes after refresh (one local banner) → Inbox; title podcast or New episode(s); body episode title or singular/plural count; needs feed refresh + permission"))
        }
        if settings.notifyOnDownloadErrors {
            parts.append(String(localized: "Download failures → Downloads (title = episode, or podcast if episode title empty, or Download failed; body = error)"))
        }
        if settings.notifyOnDownloadComplete {
            parts.append(String(localized: "Download complete → Downloads (title = episode, or podcast if episode title empty, or Download complete; body = feed when episode titled, else Download complete)"))
        }
        if settings.notifyOnSyncErrors {
            parts.append(String(localized: "Sync / login failures → Settings Sync (title Login failed, Not logged in, or Sync failed; short error body)"))
        }
        if settings.notifyOnSleepTimerEnd {
            parts.append(String(localized: "Sleep timer end → local banner + foreground haptic (one per fire; tap opens no screen)"))
        }
        return parts.joined(separator: ". ") + ". " + String(localized: "Local only — no APNs / push. OS Notifications permission required.")
    }

    @MainActor
    private func refreshNotificationAuthLabel() async {
        let status = await NewEpisodeNotificationCoordinator.authorizationStatus()
        switch status {
        case .authorized, .provisional:
            notificationAuthStatus = .allowed
        case .ephemeral:
            // Coordinators post only for authorized or provisional. Do not call this Allowed.
            notificationAuthStatus = .ephemeral
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
                .accessibilityLabel(String(localized: "Delete episode after playing"))
                .accessibilityValue(autoDeleteAfterPlayingAccessibilityValue)
                .accessibilityHint(autoDeleteAfterPlayingAccessibilityHint)
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
            .accessibilityLabel(String(localized: "Max storage"))
            .accessibilityValue(maxStorageAccessibilityValue)
            .accessibilityHint(maxStorageAccessibilityHint)
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
            .accessibilityValue(maxDownloadedEpisodesAccessibilityValue)
            .accessibilityHint(maxDownloadedEpisodesAccessibilityHint)
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
            .accessibilityValue(parallelDownloadsAccessibilityValue)
            .accessibilityHint(parallelDownloadsAccessibilityHint)
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
            .accessibilityValue(downloadAllUnplayedSoftCapAccessibilityValue)
            .accessibilityHint(downloadAllUnplayedSoftCapAccessibilityHint)
            Text(feedDownloadUnplayedSoftCapHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(feedDownloadUnplayedSoftCapHelpText)
            Button("Delete all downloads", role: .destructive) {
                showDeleteAllConfirmation = true
            }
            .disabled(downloads.downloads.isEmpty)
            .accessibilityLabel(String(localized: "Delete all downloads"))
            .accessibilityHint(
                String(localized: "Asks for confirmation, then deletes every completed offline file in the full Downloads catalog, including favorites. Ignores chip and search filters. Queued episodes and the playing download can lose their file while queue membership stays and playback continues from the stream. Local files only — keeps played status, queue, favorites, archive state, and history. Distinct from Delete played downloads and from Clear queue.")
            )
        } header: {
            Text("Downloads / Storage")
        }
    }

    /// VoiceOver for Settings → Max downloaded episodes. Count cache eviction;
    /// not the Max storage byte budget. Favorites, queued, and loaded player file protected.
    private var maxDownloadedEpisodesAccessibilityValue: String {
        let cap = settings.downloadEpisodeCacheLimit
        let label = cap.label
        if cap == .unlimited {
            return String(localized: "Unlimited. This is the default. There is no episode-count cache, so count alone does not auto-delete offline files. Max storage can still evict by byte budget. Favorites, queued episodes, and the file loaded in the player are never auto-deleted by either limit. Changing this does not delete files now, start a download, or change Parallel downloads.")
        }
        let head = String(format: String(localized: "%@. This is not the default of Unlimited."), locale: .current, label)
        return head + " " + String(localized: "When the number of completed offline downloads is over this count, played downloads that are not favorited and not queued are deleted first, oldest file first, then unplayed non-favorite non-queued by least recently used. Favorites, queued episodes, and the file loaded in the player are never auto-deleted by this cap. Maintenance runs after each successful download, when opening Settings, and on launch, and may run when you change this. Separate from the Max storage byte budget. Changing this does not invent downloads or change Parallel downloads.")
    }

    private var maxDownloadedEpisodesAccessibilityHint: String {
        String(localized: "Choices are Unlimited, 25, 50, 100, 200, and 500 episodes. The default is Unlimited. Over-limit eviction skips favorites, queued episodes, and the playing download. Not Max storage or Parallel downloads. Changing the picker may delete unprotected offline files that are over the new count.")
    }

    private var episodeCacheHelpText: String {
        String(localized: "When over the episode count, played downloads that are not favorited and not queued are deleted first (oldest file first), then unplayed non-favorite non-queued (LRU). Favorites and queued episodes are never auto-deleted by this cap. Runs after each successful download, when opening Settings, and on launch. Separate from the Max storage byte budget.")
    }

    /// VoiceOver for Settings → Parallel downloads. Cap is active transfers only;
    /// waiting FIFO is in-memory and not restored after process death.
    private var parallelDownloadsAccessibilityValue: String {
        let label = settings.maxParallelDownloads.label
        let isDefault = settings.maxParallelDownloads == .three
        let headFormat = isDefault
            ? String(localized: "%@. This is the default.")
            : String(localized: "%@. This is not the default of 3 parallel.")
        let head = String(format: headFormat, locale: .current, label)
        return head + " " + String(localized: "Only this many episode downloads run as active transfers at once. Extra downloads wait in memory until a slot frees. Waiting items are not saved across quitting the app; already-started background transfers continue after relaunch. Lowering this does not cancel transfers that already started. Changing this does not start a new download, delete files, or change Max storage or Max downloaded episodes.")
    }

    private var parallelDownloadsAccessibilityHint: String {
        String(localized: "Choices are 1 at a time through 5 parallel. The default is 3 parallel. Caps active download transfers only. Waiting downloads stay in memory and are lost if the app is killed. Already-started background tasks continue. Not Max storage, Max downloaded episodes, or Download all unplayed soft cap. Changing the picker does not invent downloads.")
    }

    private var parallelDownloadsHelpText: String {
        String(localized: "Limits how many episode downloads run as active transfers at once (1–5, default 3). Extra downloads wait in memory until a slot frees. Waiting items are not persisted across process death; already-started background URLSession tasks continue after relaunch.")
    }

    /// VoiceOver for Settings → Download all unplayed soft cap.
    /// Caps Feed detail Download all unplayed only; newest first; always capped.
    private var downloadAllUnplayedSoftCapAccessibilityValue: String {
        let cap = settings.feedDownloadUnplayedSoftCap
        let label = cap.label
        let isDefault = cap == .fifty
        let headFormat = isDefault
            ? String(localized: "%@. This is the default.")
            : String(localized: "%@. This is not the default of 50 episodes.")
        let head = String(format: headFormat, locale: .current, label)
        return head + " " + String(localized: "Feed detail Download all unplayed may enqueue at most this many newest eligible unplayed episodes at once — unplayed, not archived, not already downloaded, with an http or https enclosure. Full-feed eligibility still applies; status, episode type, and search filters do not shrink the eligible set. There is no Unlimited. Local-folder podcasts are skipped. Manual Wi‑Fi-only, Parallel downloads, and storage limits still apply when transfers start. Changing this does not start downloads now.")
    }

    private var downloadAllUnplayedSoftCapAccessibilityHint: String {
        String(localized: "Choices are 10, 25, 50, 100, and 200 episodes. The default is 50. Always soft-capped — no unlimited. Applies only to Feed detail Download all unplayed, newest first. Not Auto-download, Max storage, Max downloaded episodes, or Parallel downloads. Changing the picker does not invent downloads.")
    }

    private var feedDownloadUnplayedSoftCapHelpText: String {
        String(localized: "Limits how many newest unplayed episodes Feed detail Download all unplayed may enqueue at once (10–200, default 50). Always soft-capped — no unlimited. Full-feed eligibility still applies.")
    }

    /// VoiceOver for Settings → Delete episode after playing. Global only; per-feed Always/Never overrides.
    /// Skips favorites and defers while the local file is the active player item.
    private var autoDeleteAfterPlayingAccessibilityValue: String {
        if settings.autoDeleteAfterPlaying {
            return String(localized: "On. This is not the default. When an episode is marked played — manually or when playback finishes — its offline file is deleted. The episode row and played status stay. Favorited episodes are never deleted by this. Deletion waits while that local file is still the active player item. A per-podcast Always or Never override can replace this global choice. Changing this does not delete files now, start playback, or download.")
        }
        return String(localized: "Off. This is the default. Marking an episode played does not remove its offline file under this global setting. A per-podcast Always override can still delete that podcast’s files when marked played, except favorites and while the file is the active player item. Changing this does not delete files now, start playback, or download.")
    }

    private var autoDeleteAfterPlayingAccessibilityHint: String {
        String(localized: "On deletes the offline file when marked played. Off keeps files. Favorites are always kept. Deletion waits while the episode is still playing from that local file. Per-podcast Feed settings can Use global, Always, or Never. Default off. The switch does not delete files now.")
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

    /// VoiceOver for Settings → Max storage. Byte budget eviction; not the episode-count cache.
    /// Favorites, queued, and the loaded player file are never auto-deleted by this budget.
    private var maxStorageAccessibilityValue: String {
        switch settings.downloadStorageLimit {
        case .unlimited:
            return String(localized: "Unlimited. This is the default. There is no byte budget, so size alone does not auto-delete offline files. Max downloaded episodes can still evict by count. Favorites, queued episodes, and the file loaded in the player are never auto-deleted by either limit. Changing this does not delete files now, start a download, or change Parallel downloads.")
        case .gigabytes, .customMegabytes:
            let label = settings.downloadStorageLimit.label
            let isPresetGB: Bool
            if case .gigabytes(let gb) = settings.downloadStorageLimit, [1, 5, 10].contains(gb) {
                isPresetGB = true
            } else {
                isPresetGB = false
            }
            let headFormat = isPresetGB
                ? String(localized: "%@. This is not the default of Unlimited.")
                : String(localized: "%@. This is a custom megabyte limit, not Unlimited, and not a 1, 5, or 10 GB preset.")
            let head = String(format: headFormat, locale: .current, label)
            return head + " " + String(localized: "When used storage is over this byte budget, played downloads that are not favorited and not queued are deleted first, oldest file first, then unplayed non-favorite non-queued by least recently used file date. Favorites, queued episodes, and the file loaded in the player are never auto-deleted by this budget. Maintenance runs after each successful download, when opening Settings, and on launch, and may run when you change this. Separate from Max downloaded episodes. Changing this does not invent downloads or change Parallel downloads.")
        }
    }

    private var maxStorageAccessibilityHint: String {
        String(localized: "Presets are Unlimited, 1 GB, 5 GB, 10 GB, and Custom megabytes. The default is Unlimited. Over-limit eviction skips favorites, queued episodes, and the playing download. Not Max downloaded episodes or Parallel downloads. Changing the picker may delete unprotected offline files that are over the new budget.")
    }

    private var evictionHelpText: String {
        String(localized: "When over the limit, played downloads that are not favorited and not queued are deleted first (oldest file first), then unplayed non-favorite non-queued (LRU by file date). Favorites and queued episodes are never auto-deleted by this budget. Runs after each successful download, when opening Settings, and on launch.")
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
        return String(
            format: String(localized: "Automatic (%@ · %@)"),
            name,
            resolved
        )
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
                Text(RatingPromptCoordinator.hasRequestedReview ? String(localized: "Yes (once)") : String(localized: "Not yet"))
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
            Text("Siri / Shortcuts (lite): App Intents — Play, Pause, Play/Pause (toggle), Skip Forward, Skip Back — donated via AppShortcutsProvider for Siri / Shortcuts discoverability. Same actions via URL schemes antennapod://play, antennapod://pause, antennapod://toggle, antennapod://skip-forward, antennapod://skip-back. Intents use openAppWhenRun (open the app). Play and Play/Pause play the loaded episode, or after a cold launch the previous run’s unplayed episode shown paused in the mini player. Skip Forward and Skip Back need a loaded episode. Not background-only / no App Group shared store. Not episode or feed deep links. Not CarPlay templates (see CarPlay note).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Siri / Shortcuts"))
                .accessibilityHint(String(localized: "Lite App Intents Play Pause Skip; opens app; Play can start a cold-launch restored episode; Skip needs a loaded episode; not CarPlay templates."))
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
                .accessibilityLabel(String(localized: "CarPlay"))
                .accessibilityValue(carPlayAccessibilityValue)
                .accessibilityHint(carPlayAccessibilityHint)
        } header: {
            Text("CarPlay")
        }
    }

    /// VoiceOver for Settings → CarPlay. Caption-only honesty note: Now Playing remotes, no templates.
    private var carPlayAccessibilityValue: String {
        String(localized: "Honest partial. When audio is playing, CarPlay shows system Now Playing with play, pause, skip, and seek using the Settings intervals. Next and previous skip by those intervals. Background audio and the playback session are already set. There are no custom CarPlay templates, no CarPlay scene, and no CarPlay entitlement in this beta. Apple Watch Continue listening is a separate beta-lite target and is not CarPlay.")
    }

    private var carPlayAccessibilityHint: String {
        String(localized: "Read-only note. This screen does not turn CarPlay on or off, start playback, or install templates. Use system Now Playing while audio is playing. Not Siri Shortcuts, the homescreen widget, or Apple Watch.")
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
                .accessibilityHint(String(localized: "Caption for this sync device. Login and Sync now push it to the server when logged in; editing alone does not sync. Distinct from Regenerate device id from name."))
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
                .accessibilityHint(String(localized: "Removes the Keychain password and clears sync cursors. Host, username, device name, and device id stay for re-login. Last sync time stays; status becomes Logged out."))
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
            // Visible relative time stays; VoiceOver uses Never vs absolute finish time.
            // Stamp is the last Sync now that finished subscription URL pull/push — not login,
            // not each podcast's Last refreshed, and not cleared by logout.
            LabeledContent("Last sync") {
                if let last = gpodder.lastSyncAt {
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Last sync"))
            .accessibilityValue(lastSyncAccessibilityValue)
            .accessibilityHint(lastSyncAccessibilityHint)
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

    /// VoiceOver for Settings → Last sync. Never means no subscription sync has finished;
    /// a date is the last Sync now that completed http(s) feed URL pull/push.
    private var lastSyncAccessibilityValue: String {
        guard let last = gpodder.lastSyncAt else {
            return String(localized: "Never. No subscription sync has finished yet. Login alone does not write this time, and no timestamp is invented. This is not each podcast's Last refreshed time.")
        }
        let formatted = last.formatted(date: .abbreviated, time: .shortened)
        return String(
            format: String(localized: "Subscription sync finished %@. The stamp is written when Sync now finishes the http(s) feed URL pull and push, even if some new subscriptions failed. A failed sync that throws before finishing keeps the previous time. It is not episode actions, queue, bookmarks, or each podcast's Last refreshed time."),
            formatted
        )
    }

    private var lastSyncAccessibilityHint: String {
        String(localized: "Subscriptions only: additive http(s) feed URLs. Not a full sync. Logout does not clear this time. Local folders are not pushed.")
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
    /// `UNAuthorizationStatus.ephemeral`. Not Allowed: local banners are not posted.
    case ephemeral

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
        case .ephemeral:
            return String(localized: "Temporary")
        }
    }
}

private enum NotificationVoiceOverRole {
    case newEpisodes
    case downloadErrors
    case downloadComplete
    case syncErrors
    case sleepTimer
}
