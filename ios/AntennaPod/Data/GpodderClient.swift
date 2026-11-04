import Foundation

/// Sync backend: gpodder.net API2 vs Nextcloud Gpodder Sync app paths.
enum GpodderProvider: String, CaseIterable, Identifiable {
    case gpodderNet
    case nextcloud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gpodderNet: return "gpodder.net"
        case .nextcloud: return "Nextcloud"
        }
    }

    /// Path segment AntennaPod Android + nextcloud-gpodder append under the server root.
    /// Docs: `GET/POST …/index.php/apps/gpoddersync/subscriptions` etc.
    static let nextcloudAPIPathPrefix = "index.php/apps/gpoddersync/"

    static let nextcloudPlaceholderHost = "https://cloud.example.com/index.php/apps/gpoddersync/"
}

/// gpodder.net API v2 + Nextcloud Gpodder Sync client (URLSession + HTTP Basic).
/// gpodder shapes: https://gpoddernet.readthedocs.io/en/latest/api/reference/
/// Nextcloud paths: https://github.com/thrillfall/nextcloud-gpodder (subscriptions MVP).
struct GpodderClient {
    var baseURL: URL
    var username: String
    var password: String
    var deviceId: String
    var provider: GpodderProvider

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        host: String,
        username: String,
        password: String,
        deviceId: String,
        provider: GpodderProvider = .gpodderNet,
        session: URLSession = AppURLSession.shared
    ) throws {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.normalizeBaseURL(trimmed, provider: provider) else {
            throw GpodderError.invalidHost
        }
        self.baseURL = url
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.deviceId = deviceId
        self.provider = provider
        self.session = session
        guard !self.username.isEmpty else {
            throw GpodderError.missingCredentials
        }
        if provider == .gpodderNet, self.deviceId.isEmpty {
            throw GpodderError.missingCredentials
        }
    }

    // MARK: - Auth

    /// gpodder.net: POST /api/2/auth/{username}/login.json
    /// Nextcloud: no login endpoint — probes GET subscriptions (HTTP Basic).
    func login() async throws {
        switch provider {
        case .gpodderNet:
            let url = try apiURL("api/2/auth/\(pathEncoded(username))/login.json")
            var request = authorizedRequest(url: url, method: "POST")
            request.httpBody = Data()
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            _ = try await perform(request, expectBody: false)
        case .nextcloud:
            // Nextcloud Gpodder Sync has no auth/device API (Android login() is empty).
            // Credential check: GET subscriptions?since=0 under the API root.
            _ = try await getSubscriptionChanges(since: 0)
        }
    }

    // MARK: - Devices

    /// gpodder.net: POST /api/2/devices/{username}/{deviceid}.json
    /// Nextcloud: no-op (devices not implemented by the app).
    func updateDevice(caption: String, type: String = "mobile") async throws {
        guard provider == .gpodderNet else { return }
        let url = try apiURL("api/2/devices/\(pathEncoded(username))/\(pathEncoded(deviceId)).json")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = DeviceUpdateBody(caption: caption, type: type)
        request.httpBody = try encoder.encode(body)
        _ = try await perform(request, expectBody: false)
    }

    // MARK: - Subscriptions

    /// gpodder.net: GET /api/2/subscriptions/{username}/{deviceid}.json?since=
    /// Nextcloud: GET {apiRoot}/subscriptions?since=
    func getSubscriptionChanges(since: Int64) async throws -> SubscriptionChanges {
        let path: String
        switch provider {
        case .gpodderNet:
            path = "api/2/subscriptions/\(pathEncoded(username))/\(pathEncoded(deviceId)).json"
        case .nextcloud:
            path = "subscriptions"
        }
        var components = URLComponents(
            url: try apiURL(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "since", value: String(since))]
        guard let url = components.url else { throw GpodderError.invalidHost }
        let request = authorizedRequest(url: url, method: "GET")
        let data = try await perform(request, expectBody: true)
        return try decoder.decode(SubscriptionChanges.self, from: data)
    }

    /// gpodder.net: POST /api/2/subscriptions/{username}/{deviceid}.json
    /// Nextcloud: POST {apiRoot}/subscription_change/create
    func uploadSubscriptionChanges(add: [String], remove: [String]) async throws -> UploadChangesResponse {
        let path: String
        switch provider {
        case .gpodderNet:
            path = "api/2/subscriptions/\(pathEncoded(username))/\(pathEncoded(deviceId)).json"
        case .nextcloud:
            path = "subscription_change/create"
        }
        let url = try apiURL(path)
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = SubscriptionChangeBody(add: add, remove: remove)
        request.httpBody = try encoder.encode(body)
        let data = try await perform(request, expectBody: true)
        if data.isEmpty {
            return UploadChangesResponse(timestamp: nil, updateUrls: nil)
        }
        // Nextcloud may return only `{ "timestamp": … }` without update_urls.
        return try decoder.decode(UploadChangesResponse.self, from: data)
    }

    // MARK: - HTTP

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        AppUserAgent.apply(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let raw = "\(username):\(password)"
        let basic = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        return request
    }

    @discardableResult
    private func perform(_ request: URLRequest, expectBody: Bool) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        _ = expectBody
        guard let http = response as? HTTPURLResponse else {
            throw GpodderError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw GpodderError.unauthorized
        case 404:
            throw GpodderError.notFound
        default:
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw GpodderError.httpStatus(http.statusCode, String(snippet))
        }
    }

    private func apiURL(_ path: String) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            throw GpodderError.invalidHost
        }
        return url
    }

    private func pathEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func normalizeBaseURL(_ host: String, provider: GpodderProvider = .gpodderNet) -> URL? {
        var s = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") {
            s = "https://\(s)"
        }
        guard var components = URLComponents(string: s), components.scheme != nil, components.host != nil else {
            return nil
        }

        var path = components.path
        if provider == .nextcloud {
            path = ensureNextcloudAPIRoot(path)
        }

        // Ensure trailing slash on base so relative paths append cleanly.
        if path.isEmpty {
            path = "/"
        } else if !path.hasSuffix("/") {
            path += "/"
        }
        components.path = path
        return components.url
    }

    /// Compose Nextcloud API root: append `index.php/apps/gpoddersync/` when the user
    /// entered only the server (Android-style), or normalize an already-complete path.
    static func ensureNextcloudAPIRoot(_ path: String) -> String {
        let prefix = GpodderProvider.nextcloudAPIPathPrefix
        var p = path
        while p.hasSuffix("/") { p.removeLast() }
        let lower = p.lowercased()
        if lower.contains("gpoddersync") {
            // Already points at (or under) the app — keep as API root.
            return p.isEmpty ? "/" + prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : p
        }
        if p.isEmpty || p == "/" {
            return "/" + prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        // Server subfolder + API prefix (e.g. /nextcloud + /index.php/apps/gpoddersync).
        return p + "/" + prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Sanitize a human device caption into a gpodder device id (`[A-Za-z0-9._-]+`).
    static func sanitizeDeviceId(from name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" {
                return ch
            }
            return "_"
        }
        var id = String(mapped)
        while id.contains("__") {
            id = id.replacingOccurrences(of: "__", with: "_")
        }
        id = id.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if id.isEmpty {
            id = "antennapod_ios"
        }
        return String(id.prefix(100))
    }
}

// MARK: - DTOs

struct SubscriptionChanges: Decodable {
    let add: [String]
    let remove: [String]
    let timestamp: Int64
}

struct UploadChangesResponse: Decodable {
    let timestamp: Int64?
    let updateUrls: [[String]]?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case updateUrls = "update_urls"
    }
}

private struct SubscriptionChangeBody: Encodable {
    let add: [String]
    let remove: [String]
}

private struct DeviceUpdateBody: Encodable {
    let caption: String
    let type: String
}

enum GpodderError: LocalizedError {
    case invalidHost
    case missingCredentials
    case unauthorized
    case notFound
    case invalidResponse
    case httpStatus(Int, String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return String(localized: "Invalid sync host URL")
        case .missingCredentials:
            return String(localized: "Username and device id are required")
        case .unauthorized:
            return String(localized: "Login failed (unauthorized)")
        case .notFound:
            return String(localized: "Sync resource not found (404) — check host / Nextcloud Gpodder Sync path")
        case .invalidResponse:
            return String(localized: "Invalid response from sync server")
        case .httpStatus(let code, let body):
            if body.isEmpty {
                return String(localized: "Sync HTTP \(code)")
            }
            return String(localized: "Sync HTTP \(code): \(body)")
        case .notLoggedIn:
            return String(localized: "Not logged in to sync provider")
        }
    }
}
