import Foundation

/// gpodder.net API v2 client (URLSession + HTTP Basic).
/// Shapes follow https://gpoddernet.readthedocs.io/en/latest/api/reference/
/// Upload subscription *changes* uses POST (API docs / Android), not PUT of a full list.
struct GpodderClient {
    var baseURL: URL
    var username: String
    var password: String
    var deviceId: String

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        host: String,
        username: String,
        password: String,
        deviceId: String,
        session: URLSession = .shared
    ) throws {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.normalizeBaseURL(trimmed) else {
            throw GpodderError.invalidHost
        }
        self.baseURL = url
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.deviceId = deviceId
        self.session = session
        guard !self.username.isEmpty, !self.deviceId.isEmpty else {
            throw GpodderError.missingCredentials
        }
    }

    // MARK: - Auth

    /// POST /api/2/auth/{username}/login.json (HTTP Basic).
    func login() async throws {
        let url = try apiURL("api/2/auth/\(pathEncoded(username))/login.json")
        var request = authorizedRequest(url: url, method: "POST")
        request.httpBody = Data()
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request, expectBody: false)
    }

    // MARK: - Devices

    /// POST /api/2/devices/{username}/{deviceid}.json
    func updateDevice(caption: String, type: String = "mobile") async throws {
        let url = try apiURL("api/2/devices/\(pathEncoded(username))/\(pathEncoded(deviceId)).json")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = DeviceUpdateBody(caption: caption, type: type)
        request.httpBody = try encoder.encode(body)
        _ = try await perform(request, expectBody: false)
    }

    // MARK: - Subscriptions

    /// GET /api/2/subscriptions/{username}/{deviceid}.json?since=
    func getSubscriptionChanges(since: Int64) async throws -> SubscriptionChanges {
        var components = URLComponents(
            url: try apiURL("api/2/subscriptions/\(pathEncoded(username))/\(pathEncoded(deviceId)).json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "since", value: String(since))]
        guard let url = components.url else { throw GpodderError.invalidHost }
        let request = authorizedRequest(url: url, method: "GET")
        let data = try await perform(request, expectBody: true)
        return try decoder.decode(SubscriptionChanges.self, from: data)
    }

    /// POST /api/2/subscriptions/{username}/{deviceid}.json with `{ "add": [...], "remove": [...] }`.
    /// (API reference + AntennaPod Android; not a full-list PUT.)
    func uploadSubscriptionChanges(add: [String], remove: [String]) async throws -> UploadChangesResponse {
        let url = try apiURL("api/2/subscriptions/\(pathEncoded(username))/\(pathEncoded(deviceId)).json")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = SubscriptionChangeBody(add: add, remove: remove)
        request.httpBody = try encoder.encode(body)
        let data = try await perform(request, expectBody: true)
        if data.isEmpty {
            return UploadChangesResponse(timestamp: nil, updateUrls: nil)
        }
        return try decoder.decode(UploadChangesResponse.self, from: data)
    }

    // MARK: - HTTP

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("AntennaPod-iOS/0.1", forHTTPHeaderField: "User-Agent")
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
        // Path segment encoding (keep unreserved; encode the rest).
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func normalizeBaseURL(_ host: String) -> URL? {
        var s = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") {
            s = "https://\(s)"
        }
        guard var components = URLComponents(string: s), let scheme = components.scheme, let hostName = components.host else {
            return nil
        }
        // Ensure trailing slash on base so relative paths append cleanly.
        if !(components.path.isEmpty || components.path.hasSuffix("/")) {
            components.path += "/"
        } else if components.path.isEmpty {
            components.path = "/"
        }
        _ = scheme
        _ = hostName
        return components.url
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
            return "Invalid gpodder host URL"
        case .missingCredentials:
            return "Username and device id are required"
        case .unauthorized:
            return "Login failed (unauthorized)"
        case .notFound:
            return "gpodder resource not found (404)"
        case .invalidResponse:
            return "Invalid response from gpodder"
        case .httpStatus(let code, let body):
            if body.isEmpty {
                return "gpodder HTTP \(code)"
            }
            return "gpodder HTTP \(code): \(body)"
        case .notLoggedIn:
            return "Not logged in to gpodder.net"
        }
    }
}
