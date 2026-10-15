import Foundation

/// Subscription endpoints of gpodder.net (API 2) and the Nextcloud gpoddersync app, as pure
/// request shapes and response parsing (no networking).
///
/// | | gpodder.net | Nextcloud gpoddersync |
/// |---|---|---|
/// | pull | `GET api/2/subscriptions/{user}/{device}.json?since=` | `GET {apiRoot}/subscriptions?since=` |
/// | push | `POST api/2/subscriptions/{user}/{device}.json` | `POST {apiRoot}/subscription_change/create` |
/// | pull body | `{add, remove, timestamp}` | `{add, remove, timestamp}` |
/// | push body | `{add, remove}` | `{add, remove}` |
/// | push reply | `{timestamp, update_urls}` | `{timestamp}` (no `update_urls`), sometimes empty |
///
/// `apiRoot` is `{server}/index.php/apps/gpoddersync/`. Nextcloud has no per-device list:
/// `since=0` returns every subscription of the account.
public enum GpodderSubscriptionAPI {
    public enum Flavor: String, Sendable { case gpodderNet, nextcloud }

    /// Path relative to the API base for pulling (GET) subscription changes.
    public static func pullPath(_ flavor: Flavor, username: String, deviceId: String) -> String {
        switch flavor {
        case .gpodderNet: return "api/2/subscriptions/\(pathEncoded(username))/\(pathEncoded(deviceId)).json"
        case .nextcloud: return "subscriptions"
        }
    }

    /// Path relative to the API base for pushing (POST) subscription changes.
    public static func pushPath(_ flavor: Flavor, username: String, deviceId: String) -> String {
        switch flavor {
        case .gpodderNet: return "api/2/subscriptions/\(pathEncoded(username))/\(pathEncoded(deviceId)).json"
        case .nextcloud: return "subscription_change/create"
        }
    }

    /// Query for a pull: `since` is the timestamp the server returned last time (0 = everything).
    public static func pullQuery(since: Int64) -> [URLQueryItem] {
        [URLQueryItem(name: "since", value: String(since))]
    }

    /// Full pull URL for `base` (must end with "/").
    public static func pullURL(base: URL, flavor: Flavor, username: String, deviceId: String, since: Int64) -> URL? {
        guard let u = URL(string: pullPath(flavor, username: username, deviceId: deviceId), relativeTo: base)?.absoluteURL,
              var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = pullQuery(since: since)
        return c.url
    }

    /// JSON body for a push: `{"add": [...], "remove": [...]}`.
    public static func pushBody(add: [String], remove: [String]) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(PushBody(add: add, remove: remove))
    }

    /// Pull reply.
    public static func parsePull(_ data: Data) throws -> SubscriptionDelta {
        try JSONDecoder().decode(SubscriptionDelta.self, from: data)
    }

    /// Push reply; an empty body is a success without timestamp.
    public static func parsePush(_ data: Data) throws -> PushResult {
        if data.isEmpty {
            return PushResult(timestamp: nil, updateUrls: nil)
        }
        return try JSONDecoder().decode(PushResult.self, from: data)
    }

    /// Path segment encoding for user / device ids (unreserved characters only).
    public static func pathEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private struct PushBody: Encodable { let add: [String]; let remove: [String] }
}

/// `{add, remove, timestamp}` from a subscriptions pull.
public struct SubscriptionDelta: Decodable, Equatable, Sendable {
    public let add: [String]
    public let remove: [String]
    public let timestamp: Int64
    public init(add: [String], remove: [String], timestamp: Int64) {
        self.add = add; self.remove = remove; self.timestamp = timestamp
    }
}

/// Push reply: new timestamp and gpodder.net URL rewrites (`[[from, to], ...]`).
public struct PushResult: Decodable, Equatable, Sendable {
    public let timestamp: Int64?
    public let updateUrls: [[String]]?
    enum CodingKeys: String, CodingKey { case timestamp; case updateUrls = "update_urls" }
    public init(timestamp: Int64?, updateUrls: [[String]]?) {
        self.timestamp = timestamp; self.updateUrls = updateUrls
    }
}

/// Client-side subscription sync cursor: the server timestamp to send as `since` and the
/// equality keys of everything the server is known to have. Changes are applied to a copy and
/// committed only when the whole round succeeded, so a failed round repeats the same delta.
public struct SubscriptionSyncCursor: Equatable, Sendable {
    public var since: Int64
    public var remoteKeys: Set<String>
    public init(since: Int64 = 0, remoteKeys: Set<String> = []) { self.since = since; self.remoteKeys = remoteKeys }

    /// Server keys after a pull: `since == 0` → `add` is the full list; otherwise apply adds then removes.
    public func applyingPull(_ delta: SubscriptionDelta) -> Set<String> {
        if since == 0 { return FeedURLEquality.keys(delta.add) }
        var keys = remoteKeys
        keys.formUnion(FeedURLEquality.keys(delta.add))
        keys.subtract(FeedURLEquality.keys(delta.remove))
        return keys
    }

    /// Server keys after a successful push of `uploaded`, with gpodder.net URL rewrites.
    public static func applyingPush(_ keys: Set<String>, uploaded: [String], result: PushResult) -> Set<String> {
        var keys = keys
        for pair in result.updateUrls ?? [] where pair.count >= 2 {
            let from = FeedURLEquality.key(pair[0]), to = FeedURLEquality.key(pair[1])
            if !from.isEmpty { keys.remove(from) }
            if !to.isEmpty { keys.insert(to) }
        }
        keys.formUnion(FeedURLEquality.keys(uploaded))
        return keys
    }

    /// Cursor after a successful round: the push timestamp when there was a push that returned
    /// one, else the pull timestamp.
    public static func committed(pull: SubscriptionDelta, keys: Set<String>, push: PushResult?) -> SubscriptionSyncCursor {
        SubscriptionSyncCursor(since: push?.timestamp ?? pull.timestamp, remoteKeys: keys)
    }

    /// Cursor after Reset app data: like a first sync.
    public static let reset = SubscriptionSyncCursor()
}
