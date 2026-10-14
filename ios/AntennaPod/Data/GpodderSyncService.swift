import Foundation

/// gpodder.net / Nextcloud Gpodder Sync prefs + orchestration.
/// **Honest coverage (beta):** syncs **http(s) subscription feed URLs** (additive pull/push,
/// plus a one-shot account-wide import) and **episode play actions** (position / played) for
/// episodes whose media URL matches. Does **not** sync queue, favorites, bookmarks, tags,
/// downloads, local folder feeds (`local-folder://`), archive, or inbox.
/// Password lives in Keychain only — never UserDefaults / backup JSON.
@MainActor
final class GpodderSyncService: ObservableObject {
    static let defaultHost = "https://gpodder.net"

    private enum Keys {
        static let provider = "gpodder.provider"
        static let host = "gpodder.host"
        static let username = "gpodder.username"
        static let deviceId = "gpodder.deviceId"
        static let deviceName = "gpodder.deviceName"
        static let isLoggedIn = "gpodder.isLoggedIn"
        static let lastSyncAt = "gpodder.lastSyncAt"
        static let lastSyncError = "gpodder.lastSyncError"
        static let lastSyncStatus = "gpodder.lastSyncStatus"
        static let subscriptionTimestamp = "gpodder.subscriptionTimestamp"
        /// URLs known to be on the server for this device (additive merge helper).
        static let knownRemoteURLs = "gpodder.knownRemoteURLs"
        /// Server cursor for GET episode actions.
        static let episodeActionsTimestamp = "gpodder.episodeActionsTimestamp"
        /// Local epoch ms of the last successful episode-action upload.
        static let episodeUploadCursorMs = "gpodder.episodeUploadCursorMs"
    }

    /// gpodder.net (API2) vs Nextcloud Gpodder Sync (different path root).
    @Published var provider: GpodderProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider)
        }
    }

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: Keys.host) }
    }

    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Keys.username) }
    }

    /// Editable caption shown on gpodder.net (device name).
    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: Keys.deviceName) }
    }

    /// Stable device id (generated once; sanitized `[A-Za-z0-9._-]+`).
    @Published private(set) var deviceId: String {
        didSet { UserDefaults.standard.set(deviceId, forKey: Keys.deviceId) }
    }

    @Published private(set) var isLoggedIn: Bool {
        didSet { UserDefaults.standard.set(isLoggedIn, forKey: Keys.isLoggedIn) }
    }

    @Published var lastSyncAt: Date? {
        didSet {
            if let lastSyncAt {
                UserDefaults.standard.set(lastSyncAt.timeIntervalSince1970, forKey: Keys.lastSyncAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastSyncAt)
            }
        }
    }

    @Published var lastSyncError: String? {
        didSet {
            if let lastSyncError {
                UserDefaults.standard.set(lastSyncError, forKey: Keys.lastSyncError)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastSyncError)
            }
        }
    }

    @Published var lastSyncStatus: String {
        didSet { UserDefaults.standard.set(lastSyncStatus, forKey: Keys.lastSyncStatus) }
    }

    @Published var isBusy = false

    /// gpodder.net devices on the account (empty for Nextcloud, which has no device API).
    @Published private(set) var devices: [GpodderDevice] = []

    /// Subscription import progress (`done` of `total` feeds), nil when idle.
    @Published private(set) var importProgress: (done: Int, total: Int)?

    /// Feeds that failed during the last import or sync (URL + error), shown in Settings.
    @Published private(set) var importFailures: [GpodderImportFailure] = []

    /// Wired from `AntennaPodApp` for sync-error local notifications.
    weak var settings: AppSettings?

    /// Draft password field (never persisted in UserDefaults; Keychain only on Login).
    @Published var passwordDraft: String = ""

    private var subscriptionTimestamp: Int64 {
        get {
            Int64(UserDefaults.standard.double(forKey: Keys.subscriptionTimestamp))
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: Keys.subscriptionTimestamp)
        }
    }

    private var episodeActionsTimestamp: Int64 {
        get { Int64(UserDefaults.standard.double(forKey: Keys.episodeActionsTimestamp)) }
        set { UserDefaults.standard.set(Double(newValue), forKey: Keys.episodeActionsTimestamp) }
    }

    private var episodeUploadCursorMs: Int64 {
        get { Int64(UserDefaults.standard.double(forKey: Keys.episodeUploadCursorMs)) }
        set { UserDefaults.standard.set(Double(newValue), forKey: Keys.episodeUploadCursorMs) }
    }

    private func resetCursors() {
        subscriptionTimestamp = 0
        knownRemoteURLs = []
        episodeActionsTimestamp = 0
        episodeUploadCursorMs = 0
    }

    private var knownRemoteURLs: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: Keys.knownRemoteURLs) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: Keys.knownRemoteURLs)
        }
    }

    init() {
        let providerRaw = UserDefaults.standard.string(forKey: Keys.provider) ?? GpodderProvider.gpodderNet.rawValue
        let initialProvider = GpodderProvider(rawValue: providerRaw) ?? .gpodderNet
        provider = initialProvider
        let storedHost = UserDefaults.standard.string(forKey: Keys.host)
        if let storedHost, !storedHost.isEmpty {
            host = storedHost
        } else {
            host = initialProvider == .gpodderNet ? Self.defaultHost : ""
        }
        let initialUsername = UserDefaults.standard.string(forKey: Keys.username) ?? ""
        username = initialUsername
        let storedName = UserDefaults.standard.string(forKey: Keys.deviceName)
        let defaultName = "AntennaPod iOS"
        let initialDeviceName = (storedName?.isEmpty == false) ? storedName! : defaultName
        deviceName = initialDeviceName
        if let storedId = UserDefaults.standard.string(forKey: Keys.deviceId), !storedId.isEmpty {
            deviceId = storedId
        } else {
            let generated = Self.makeInitialDeviceId(caption: initialDeviceName)
            deviceId = generated
            UserDefaults.standard.set(generated, forKey: Keys.deviceId)
        }
        isLoggedIn = UserDefaults.standard.bool(forKey: Keys.isLoggedIn)
            && GpodderKeychain.loadPassword() != nil
            && !initialUsername.isEmpty
        if UserDefaults.standard.object(forKey: Keys.lastSyncAt) != nil {
            lastSyncAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Keys.lastSyncAt))
        } else {
            lastSyncAt = nil
        }
        lastSyncError = UserDefaults.standard.string(forKey: Keys.lastSyncError)
        lastSyncStatus = UserDefaults.standard.string(forKey: Keys.lastSyncStatus) ?? String(localized: "Never synced")
        // Do not echo Keychain password into the draft field.
        passwordDraft = ""
    }

    /// Regenerate device id from the current caption (user-triggered).
    func regenerateDeviceIdFromName() {
        deviceId = GpodderClient.sanitizeDeviceId(from: deviceName)
        // Force a full subscription pull next sync (new device id).
        resetCursors()
    }

    /// Use an existing gpodder.net device (from `devices`): adopts its id + caption and
    /// resets cursors so the next sync pulls that device's full subscription list.
    func selectDevice(_ device: GpodderDevice) {
        guard device.id != deviceId else { return }
        deviceId = device.id
        if !device.caption.isEmpty { deviceName = device.caption }
        resetCursors()
        lastSyncStatus = String(localized: "Device selected: \(device.caption.isEmpty ? device.id : device.caption) — run Sync now")
    }

    /// Create (or rename) this device on the server from `deviceName`, with a fresh id.
    func createDevice() async {
        guard !isBusy, isLoggedIn, let password = GpodderKeychain.loadPassword() else { return }
        isBusy = true
        defer { isBusy = false }
        deviceId = Self.makeInitialDeviceId(caption: deviceName)
        resetCursors()
        do {
            let client = try makeClient(password: password)
            try await client.login()
            try await client.updateDevice(caption: deviceName.isEmpty ? "AntennaPod iOS" : deviceName, type: "mobile")
            devices = (try? await client.listDevices()) ?? devices
            lastSyncError = nil
            lastSyncStatus = String(localized: "Device created: \(deviceId)")
        } catch {
            recordFailure(error: error.localizedDescription, status: String(localized: "Device creation failed"))
        }
    }

    /// Reload the gpodder.net device list (no-op for Nextcloud).
    func refreshDevices() async {
        guard isLoggedIn, provider == .gpodderNet, let password = GpodderKeychain.loadPassword() else { return }
        do {
            let client = try makeClient(password: password)
            try await client.login()
            devices = try await client.listDevices()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    /// Switch provider preset: logs out and applies default host (gpodder.net) or clears for Nextcloud.
    func selectProvider(_ newProvider: GpodderProvider) {
        guard newProvider != provider else { return }
        if isLoggedIn {
            logout()
        }
        provider = newProvider
        switch newProvider {
        case .gpodderNet:
            if host.isEmpty || host.lowercased().contains("gpoddersync") {
                host = Self.defaultHost
            }
        case .nextcloud:
            if host == Self.defaultHost || host.lowercased().contains("gpodder.net") {
                host = ""
            }
        }
        resetCursors()
        devices = []
        lastSyncStatus = String(localized: "Provider: \(newProvider.label)")
    }

    // MARK: - Login / Logout

    func login() async {
        guard !isBusy else { return }
        isBusy = true
        lastSyncError = nil
        defer { isBusy = false }

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = passwordDraft
        guard !user.isEmpty, !pass.isEmpty else {
            recordFailure(
                error: String(localized: "Enter username and password"),
                status: String(localized: "Login failed"),
                notificationTitle: String(localized: "Login failed")
            )
            return
        }
        if provider == .nextcloud, host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordFailure(
                error: String(localized: "Enter Nextcloud base URL (e.g. https://cloud.example.com/index.php/apps/gpoddersync/)"),
                status: String(localized: "Login failed"),
                notificationTitle: String(localized: "Login failed")
            )
            return
        }
        username = user

        do {
            // Validate first; only a working password is written to the Keychain.
            let client = try makeClient(password: pass)
            try await client.login()
            try await client.updateDevice(caption: deviceName.isEmpty ? "AntennaPod iOS" : deviceName, type: "mobile")
            try GpodderKeychain.savePassword(pass)
            devices = (try? await client.listDevices()) ?? []
            isLoggedIn = true
            passwordDraft = ""
            lastSyncError = nil
            lastSyncStatus = String(localized: "Logged in — run Import all subscriptions or Sync now")
        } catch {
            isLoggedIn = false
            recordFailure(
                error: error.localizedDescription,
                status: String(localized: "Login failed"),
                notificationTitle: String(localized: "Login failed")
            )
        }
    }

    func logout() {
        GpodderKeychain.deletePassword()
        isLoggedIn = false
        passwordDraft = ""
        resetCursors()
        devices = []
        importFailures = []
        lastSyncError = nil
        lastSyncStatus = String(localized: "Logged out")
        // Keep host / username / device id+name so re-login is easy.
    }

    // MARK: - Import

    /// One-shot import of **every** subscription on the account (gpodder.net: all devices;
    /// Nextcloud: full list). Subscribes missing http(s) feeds, deduped against local feeds
    /// and within the list, with per-feed progress and errors. Never unsubscribes anything.
    func importAllSubscriptions(store: PodcastStore) async {
        guard !isBusy else { return }
        guard isLoggedIn, let password = GpodderKeychain.loadPassword() else {
            recordFailure(
                error: GpodderError.notLoggedIn.localizedDescription,
                status: String(localized: "Not logged in"),
                notificationTitle: String(localized: "Not logged in")
            )
            return
        }
        isBusy = true
        lastSyncError = nil
        lastSyncStatus = String(localized: "Importing subscriptions…")
        defer { isBusy = false }
        do {
            let client = try makeClient(password: password)
            try await client.login()
            let remote = try await client.getAllSubscriptionURLs()
            let result = await subscribeMissing(remote, store: store)
            var remoteKeys = knownRemoteURLs
            for url in remote { remoteKeys.insert(Self.normalizeFeedURL(url)) }
            knownRemoteURLs = remoteKeys
            lastSyncAt = Date()
            lastSyncStatus = String(localized: "Import: \(remote.count) on server · \(result.subscribed) subscribed · \(result.skipped) already local · \(result.failures.count) failed")
            if let first = result.failures.first {
                recordFailure(error: "\(first.url): \(first.message)", status: lastSyncStatus)
            }
        } catch {
            recordFailure(error: error.localizedDescription, status: String(localized: "Import failed"))
        }
    }

    /// Subscribe every not-yet-local http(s) URL; updates `importProgress` / `importFailures`.
    private func subscribeMissing(
        _ remote: [String],
        store: PodcastStore
    ) async -> (subscribed: Int, skipped: Int, failures: [GpodderImportFailure]) {
        let todo = GpodderSyncLogic.urlsToImport(remote: remote, localFeedURLs: store.feeds.map(\.feedUrl))
        let distinctRemote = Set(remote.map(Self.normalizeFeedURL).filter { $0.hasPrefix("http") }).count
        var failures: [GpodderImportFailure] = []
        var subscribed = 0
        importFailures = []
        importProgress = todo.isEmpty ? nil : (0, todo.count)
        for (index, url) in todo.enumerated() {
            do {
                try await store.subscribeQuietly(feedUrl: url)
                subscribed += 1
            } catch {
                failures.append(GpodderImportFailure(url: url, message: error.localizedDescription))
            }
            importProgress = (index + 1, todo.count)
        }
        importProgress = nil
        importFailures = failures
        return (subscribed, max(0, distinctRemote - todo.count), failures)
    }

    // MARK: - Sync

    /// Pull remote subscription URLs → subscribe missing locally; push local http(s) URLs not on server.
    /// Additive merge: remote `remove` does **not** unsubscribe local feeds (honest MVP).
    /// Local folder feeds, non-http URLs, episode actions, queue/favorites/bookmarks/tags/downloads
    /// are **never** uploaded — status always reports partial subscriptions sync (never “full sync”).
    func syncNow(store: PodcastStore) async {
        guard !isBusy else { return }
        guard isLoggedIn else {
            recordFailure(
                error: GpodderError.notLoggedIn.localizedDescription,
                status: String(localized: "Not logged in"),
                notificationTitle: String(localized: "Not logged in")
            )
            return
        }
        guard let password = GpodderKeychain.loadPassword() else {
            isLoggedIn = false
            recordFailure(
                error: String(localized: "Password missing from Keychain — log in again"),
                status: String(localized: "Not logged in"),
                notificationTitle: String(localized: "Not logged in")
            )
            return
        }

        isBusy = true
        lastSyncError = nil
        lastSyncStatus = String(localized: "Syncing…")
        defer { isBusy = false }

        do {
            let client = try makeClient(password: password)
            try await client.login()
            try await client.updateDevice(
                caption: deviceName.isEmpty ? "AntennaPod iOS" : deviceName,
                type: "mobile"
            )

            let since = subscriptionTimestamp
            let changes = try await client.getSubscriptionChanges(since: since)

            var remote = knownRemoteURLs
            if since == 0 {
                // Fresh device / first sync: `add` is the full current list.
                remote = Set(changes.add.map { Self.normalizeFeedURL($0) }.filter { !$0.isEmpty })
            } else {
                for url in changes.add {
                    let n = Self.normalizeFeedURL(url)
                    if !n.isEmpty { remote.insert(n) }
                }
                for url in changes.remove {
                    let n = Self.normalizeFeedURL(url)
                    if !n.isEmpty { remote.remove(n) }
                }
            }

            // Pull: subscribe missing (deduped, per-feed progress + errors).
            let localNormalized = Set(store.feeds.map { Self.normalizeFeedURL($0.feedUrl) }.filter { !$0.isEmpty })
            let pulled = await subscribeMissing(changes.add, store: store)
            let subscribed = pulled.subscribed
            let subscribeFailures = pulled.failures.map { "\($0.url): \($0.message)" }

            // Remote removes are intentionally ignored locally (additive merge).
            let ignoredRemoves = changes.remove.filter {
                let n = Self.normalizeFeedURL($0)
                return !n.isEmpty && localNormalized.contains(n)
            }

            // Push: local http(s) URLs not known on server. Upload the original
            // path/query case (`syncFeedURL`); `remote` stays a lowercased equality set.
            var toUpload: [String] = []
            var seenUploadKeys = Set<String>()
            for feed in store.feeds {
                let fetchURL = Self.syncFeedURL(feed.feedUrl)
                let key = Self.normalizeFeedURL(fetchURL)
                guard !key.isEmpty, key.hasPrefix("http") else { continue }
                guard !remote.contains(key) else { continue }
                guard seenUploadKeys.insert(key).inserted else { continue }
                toUpload.append(fetchURL)
            }
            var uploadTimestamp = changes.timestamp
            if !toUpload.isEmpty {
                let upload = try await client.uploadSubscriptionChanges(add: toUpload, remove: [])
                if let ts = upload.timestamp {
                    uploadTimestamp = ts
                }
                // Apply server URL rewrites if present.
                if let pairs = upload.updateUrls {
                    for pair in pairs where pair.count >= 2 {
                        let from = Self.normalizeFeedURL(pair[0])
                        let to = Self.normalizeFeedURL(pair[1])
                        if !from.isEmpty { remote.remove(from) }
                        if !to.isEmpty { remote.insert(to) }
                    }
                }
                for u in toUpload { remote.insert(Self.normalizeFeedURL(u)) }
            }

            knownRemoteURLs = remote
            subscriptionTimestamp = uploadTimestamp

            let episodeResult = try await syncEpisodeActions(client: client, store: store)
            lastSyncAt = Date()

            let localFolderOmitted = store.feeds.filter { LocalFolderFeed.isLocalFolderFeed($0) }.count
            // Always frame as partial subscriptions sync — never invent “full sync”.
            var parts: [String] = [String(localized: "Subscriptions sync (partial)")]
            parts.append(String(localized: "pulled \(changes.add.count) remote add(s)"))
            if subscribed > 0 { parts.append(String(localized: "subscribed \(subscribed) new")) }
            if !toUpload.isEmpty { parts.append(String(localized: "pushed \(toUpload.count) local http(s)")) }
            if !ignoredRemoves.isEmpty {
                parts.append(String(localized: "ignored \(ignoredRemoves.count) remote remove(s) (additive)"))
            }
            if localFolderOmitted > 0 {
                parts.append(String(localized: "omitted \(localFolderOmitted) local folder feed(s)"))
            }
            if !subscribeFailures.isEmpty {
                parts.append(String(localized: "\(subscribeFailures.count) subscribe error(s)"))
            }
            parts.append(String(localized: "episodes: \(episodeResult.applied) updated from server, \(episodeResult.uploaded) uploaded"))
            parts.append(String(localized: "queue / favorites / bookmarks / tags / downloads: local-only"))
            lastSyncStatus = parts.joined(separator: " · ")
            if let first = subscribeFailures.first {
                // Sync completed with subscribe errors — still surface + notify.
                recordFailure(error: first, status: lastSyncStatus)
            } else {
                lastSyncError = nil
            }
        } catch {
            recordFailure(error: error.localizedDescription, status: String(localized: "Sync failed"))
        }
    }


    /// Download remote play actions → apply newer position / played locally; upload local
    /// changes since the last cursor. Computed before applying so remote updates are not echoed.
    private func syncEpisodeActions(
        client: GpodderClient,
        store: PodcastStore
    ) async throws -> (applied: Int, uploaded: Int) {
        let started = Int64(Date().timeIntervalSince1970 * 1000)
        let remote = try await client.getEpisodeActions(since: episodeActionsTimestamp)
        var refs: [GpodderSyncLogic.EpisodeRef] = []
        for feed in store.feeds where !LocalFolderFeed.isLocalFolderFeed(feed) {
            for episode in feed.episodes {
                refs.append(.init(episodeId: episode.id, feedUrl: feed.feedUrl, mediaUrl: episode.downloadUrl))
            }
        }
        let updates = GpodderSyncLogic.remoteUpdates(
            actions: remote.actions, refs: refs, localStates: store.playbackStates
        )
        let updatedIds = Set(updates.map(\.episodeId))
        let outgoing = GpodderSyncLogic.localActions(
            refs: refs, localStates: store.playbackStates,
            sinceMs: episodeUploadCursorMs, deviceId: deviceId
        ).filter { !updatedIds.contains($0.guid ?? "") }

        for update in updates {
            if update.isPlayed, !store.isPlayed(update.episodeId) {
                store.markPlayed(update.episodeId)
            }
            var state = store.playbackState(for: update.episodeId)
            state.isPlayed = state.isPlayed || update.isPlayed
            if !update.isPlayed { state.positionSeconds = update.positionSeconds }
            if update.durationSeconds > 0 { state.durationSeconds = update.durationSeconds }
            state.updatedAtEpochMs = update.updatedAtEpochMs
            if update.isPlayed || update.positionSeconds > 1 {
                state.lastPlayedAtEpochMs = max(state.lastPlayedAtEpochMs ?? 0, update.updatedAtEpochMs)
            }
            store.playbackStates[update.episodeId] = state
        }

        var timestamp = remote.timestamp
        if !outgoing.isEmpty, let ts = try await client.uploadEpisodeActions(outgoing) {
            timestamp = max(timestamp, ts)
        }
        episodeActionsTimestamp = timestamp
        episodeUploadCursorMs = started
        return (updates.count, outgoing.count)
    }

    /// Persist failure + optional local notification (Settings toggle + permission).
    /// `notificationTitle` is the banner title (Login failed / Not logged in / Sync failed default).
    private func recordFailure(
        error message: String,
        status: String,
        notificationTitle: String = String(localized: "Sync failed")
    ) {
        lastSyncError = message
        lastSyncStatus = status
        let msg = message
        let title = notificationTitle
        let settings = self.settings
        Task {
            await SyncErrorNotificationCoordinator.notifyIfNeeded(
                message: msg,
                title: title,
                settings: settings
            )
        }
    }

    // MARK: - Helpers

    private func makeClient(password: String) throws -> GpodderClient {
        let resolvedHost: String
        switch provider {
        case .gpodderNet:
            resolvedHost = host.isEmpty ? Self.defaultHost : host
        case .nextcloud:
            guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GpodderError.invalidHost
            }
            resolvedHost = host
        }
        return try GpodderClient(
            host: resolvedHost,
            username: username,
            password: password,
            deviceId: deviceId,
            provider: provider
        )
    }

    static func makeInitialDeviceId(caption: String) -> String {
        let base = GpodderClient.sanitizeDeviceId(from: caption.isEmpty ? "AntennaPod iOS" : caption)
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        return "\(base)_\(suffix)"
    }

    /// Feed URL to fetch or upload: trim, drop trailing slashes, lowercase the scheme only.
    /// Path, host, and query keep their original case so case-sensitive paths and tokens survive sync.
    nonisolated static func syncFeedURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if let schemeSep = s.range(of: "://") {
            let scheme = s[..<schemeSep.lowerBound].lowercased()
            s = scheme + s[schemeSep.lowerBound...]
        }
        return s
    }

    /// Equality key only (trim, strip trailing slashes, lowercase the whole URL).
    /// Never pass this to subscribe or upload — use `syncFeedURL` for the real request.
    nonisolated static func normalizeFeedURL(_ raw: String) -> String {
        syncFeedURL(raw).lowercased()
    }

    // MARK: - Data backup

    /// gpodder / Nextcloud prefs for iOS JSON backup — **password never included** (Keychain only).
    func backupSnapshot() -> GpodderBackupSnapshot {
        GpodderBackupSnapshot(
            provider: provider.rawValue,
            host: host,
            username: username,
            deviceId: deviceId,
            deviceName: deviceName,
            isLoggedIn: isLoggedIn,
            lastSyncAtEpoch: lastSyncAt?.timeIntervalSince1970,
            lastSyncStatus: lastSyncStatus,
            lastSyncError: lastSyncError,
            subscriptionTimestamp: subscriptionTimestamp,
            knownRemoteURLs: Array(knownRemoteURLs).sorted(),
            passwordIncluded: false
        )
    }

    /// Restore prefs from backup. Password stays in Keychain if still present on this device;
    /// otherwise `isLoggedIn` is forced off so the user re-enters the password.
    func applyBackupSnapshot(_ snap: GpodderBackupSnapshot) {
        provider = GpodderProvider(rawValue: snap.provider) ?? .gpodderNet
        host = snap.host
        username = snap.username
        deviceName = snap.deviceName
        if !snap.deviceId.isEmpty {
            deviceId = snap.deviceId
        }
        lastSyncStatus = snap.lastSyncStatus
        lastSyncError = snap.lastSyncError
        if let epoch = snap.lastSyncAtEpoch {
            lastSyncAt = Date(timeIntervalSince1970: epoch)
        } else {
            lastSyncAt = nil
        }
        subscriptionTimestamp = snap.subscriptionTimestamp
        knownRemoteURLs = Set(snap.knownRemoteURLs)
        passwordDraft = ""
        let hasPassword = GpodderKeychain.loadPassword() != nil
        // Never claim logged-in without a Keychain password (cross-device restore).
        isLoggedIn = snap.isLoggedIn && hasPassword
        if snap.isLoggedIn && !hasPassword {
            lastSyncStatus = String(localized: "Restored from backup — re-enter password to login (Keychain secret not in backup)")
        }
    }
}

/// One feed that could not be subscribed during gpodder import / sync.
struct GpodderImportFailure: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let message: String
}

/// Codable gpodder prefs blob (`gpodder-prefs.json`). Password is never serialized.
struct GpodderBackupSnapshot: Codable, Equatable {
    var provider: String
    var host: String
    var username: String
    var deviceId: String
    var deviceName: String
    var isLoggedIn: Bool
    var lastSyncAtEpoch: Double?
    var lastSyncStatus: String
    var lastSyncError: String?
    var subscriptionTimestamp: Int64
    var knownRemoteURLs: [String]
    /// Always false in exports; documents honesty in the JSON itself.
    var passwordIncluded: Bool
}
