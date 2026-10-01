import Foundation

/// gpodder.net sync prefs + orchestration (subscriptions MVP; episode actions stubbed).
@MainActor
final class GpodderSyncService: ObservableObject {
    static let defaultHost = "https://gpodder.net"

    private enum Keys {
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
        host = UserDefaults.standard.string(forKey: Keys.host) ?? Self.defaultHost
        username = UserDefaults.standard.string(forKey: Keys.username) ?? ""
        let storedName = UserDefaults.standard.string(forKey: Keys.deviceName)
        let defaultName = "AntennaPod iOS"
        deviceName = (storedName?.isEmpty == false) ? storedName! : defaultName
        if let storedId = UserDefaults.standard.string(forKey: Keys.deviceId), !storedId.isEmpty {
            deviceId = storedId
        } else {
            let generated = Self.makeInitialDeviceId(caption: deviceName)
            deviceId = generated
            UserDefaults.standard.set(generated, forKey: Keys.deviceId)
        }
        isLoggedIn = UserDefaults.standard.bool(forKey: Keys.isLoggedIn)
            && GpodderKeychain.loadPassword() != nil
            && !username.isEmpty
        if UserDefaults.standard.object(forKey: Keys.lastSyncAt) != nil {
            lastSyncAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Keys.lastSyncAt))
        } else {
            lastSyncAt = nil
        }
        lastSyncError = UserDefaults.standard.string(forKey: Keys.lastSyncError)
        lastSyncStatus = UserDefaults.standard.string(forKey: Keys.lastSyncStatus) ?? "Never synced"
        // Do not echo Keychain password into the draft field.
        passwordDraft = ""
    }

    /// Regenerate device id from the current caption (user-triggered).
    func regenerateDeviceIdFromName() {
        deviceId = GpodderClient.sanitizeDeviceId(from: deviceName)
        // Force a full subscription pull next sync (new device id).
        subscriptionTimestamp = 0
        knownRemoteURLs = []
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
            lastSyncError = "Enter username and password"
            lastSyncStatus = "Login failed"
            return
        }
        username = user

        do {
            try GpodderKeychain.savePassword(pass)
            let client = try makeClient(password: pass)
            try await client.login()
            try await client.updateDevice(caption: deviceName.isEmpty ? "AntennaPod iOS" : deviceName, type: "mobile")
            isLoggedIn = true
            passwordDraft = ""
            lastSyncError = nil
            lastSyncStatus = "Logged in"
        } catch {
            isLoggedIn = false
            lastSyncError = error.localizedDescription
            lastSyncStatus = "Login failed"
        }
    }

    func logout() {
        GpodderKeychain.deletePassword()
        isLoggedIn = false
        passwordDraft = ""
        subscriptionTimestamp = 0
        knownRemoteURLs = []
        lastSyncError = nil
        lastSyncStatus = "Logged out"
        // Keep host / username / device id+name so re-login is easy.
    }

    // MARK: - Sync

    /// Pull remote subscription URLs → subscribe missing locally; push local URLs not on server.
    /// Additive merge: remote `remove` does **not** unsubscribe local feeds (honest MVP).
    /// Episode actions are not synced yet.
    func syncNow(store: PodcastStore) async {
        guard !isBusy else { return }
        guard isLoggedIn else {
            lastSyncError = GpodderError.notLoggedIn.localizedDescription
            lastSyncStatus = "Not logged in"
            return
        }
        guard let password = GpodderKeychain.loadPassword() else {
            isLoggedIn = false
            lastSyncError = "Password missing from Keychain — log in again"
            lastSyncStatus = "Not logged in"
            return
        }

        isBusy = true
        lastSyncError = nil
        lastSyncStatus = "Syncing…"
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

            // Pull: subscribe missing (reuse subscribeQuietly / FeedRepository pipeline).
            var subscribed = 0
            var subscribeFailures: [String] = []
            let localNormalized = Set(store.feeds.map { Self.normalizeFeedURL($0.feedUrl) }.filter { !$0.isEmpty })
            for raw in changes.add {
                let url = Self.normalizeFeedURL(raw)
                guard url.hasPrefix("http") else { continue }
                if localNormalized.contains(url) { continue }
                // Also skip if any local feed matches case-insensitively / trailing slash already normalized.
                if store.feeds.contains(where: { Self.normalizeFeedURL($0.feedUrl) == url }) {
                    continue
                }
                do {
                    try await store.subscribeQuietly(feedUrl: url)
                    subscribed += 1
                } catch {
                    subscribeFailures.append("\(url): \(error.localizedDescription)")
                }
            }

            // Remote removes are intentionally ignored locally (additive merge).
            let ignoredRemoves = changes.remove.filter {
                let n = Self.normalizeFeedURL($0)
                return !n.isEmpty && localNormalized.contains(n)
            }

            // Push: local feed URLs not known on server.
            let refreshedLocal = store.feeds.map { Self.normalizeFeedURL($0.feedUrl) }.filter {
                !$0.isEmpty && $0.hasPrefix("http")
            }
            let toUpload = refreshedLocal.filter { !remote.contains($0) }
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
                for u in toUpload { remote.insert(u) }
            }

            knownRemoteURLs = remote
            subscriptionTimestamp = uploadTimestamp
            lastSyncAt = Date()

            var parts: [String] = []
            parts.append("Pulled \(changes.add.count) remote add(s)")
            if subscribed > 0 { parts.append("subscribed \(subscribed) new") }
            if !toUpload.isEmpty { parts.append("pushed \(toUpload.count) local") }
            if !ignoredRemoves.isEmpty {
                parts.append("ignored \(ignoredRemoves.count) remote remove(s) (additive)")
            }
            if !subscribeFailures.isEmpty {
                parts.append("\(subscribeFailures.count) subscribe error(s)")
            }
            parts.append("episode actions: not synced yet")
            lastSyncStatus = parts.joined(separator: " · ")
            if let first = subscribeFailures.first {
                lastSyncError = first
            } else {
                lastSyncError = nil
            }
        } catch {
            lastSyncError = error.localizedDescription
            lastSyncStatus = "Sync failed"
        }
    }

    // MARK: - Helpers

    private func makeClient(password: String) throws -> GpodderClient {
        try GpodderClient(
            host: host.isEmpty ? Self.defaultHost : host,
            username: username,
            password: password,
            deviceId: deviceId
        )
    }

    static func makeInitialDeviceId(caption: String) -> String {
        let base = GpodderClient.sanitizeDeviceId(from: caption.isEmpty ? "AntennaPod iOS" : caption)
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        return "\(base)_\(suffix)"
    }

    /// Lowercase + trim trailing slash for crude URL equality (MVP).
    static func normalizeFeedURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s.lowercased()
    }
}
