import Foundation
import XCTest
@testable import PodcastCore

// MARK: - Request / response shape

final class GpodderSubscriptionAPIShapeTests: XCTestCase {
    let ncBase = URL(string: "https://cloud.example.com/index.php/apps/gpoddersync/")!
    let gpBase = URL(string: "https://gpodder.net/")!

    func testNextcloudPullURL() {
        let u = GpodderSubscriptionAPI.pullURL(base: ncBase, flavor: .nextcloud, username: "axel", deviceId: "ios", since: 0)
        XCTAssertEqual(u?.absoluteString, "https://cloud.example.com/index.php/apps/gpoddersync/subscriptions?since=0")
        let inc = GpodderSubscriptionAPI.pullURL(base: ncBase, flavor: .nextcloud, username: "axel", deviceId: "ios", since: 1_697_000_123)
        XCTAssertEqual(inc?.absoluteString, "https://cloud.example.com/index.php/apps/gpoddersync/subscriptions?since=1697000123")
    }

    func testNextcloudPushPathAndSubfolderInstall() {
        XCTAssertEqual(GpodderSubscriptionAPI.pushPath(.nextcloud, username: "u", deviceId: "d"), "subscription_change/create")
        let sub = URL(string: "https://host.example/nextcloud/index.php/apps/gpoddersync/")!
        XCTAssertEqual(URL(string: GpodderSubscriptionAPI.pushPath(.nextcloud, username: "u", deviceId: "d"), relativeTo: sub)?.absoluteString,
                       "https://host.example/nextcloud/index.php/apps/gpoddersync/subscription_change/create")
    }

    func testGpodderNetPullAndPushShareTheDevicePath() {
        let pull = GpodderSubscriptionAPI.pullURL(base: gpBase, flavor: .gpodderNet, username: "axel l", deviceId: "ios/1", since: 7)
        XCTAssertEqual(pull?.absoluteString, "https://gpodder.net/api/2/subscriptions/axel%20l/ios%2F1.json?since=7")
        XCTAssertEqual(GpodderSubscriptionAPI.pushPath(.gpodderNet, username: "axel", deviceId: "ios"), "api/2/subscriptions/axel/ios.json")
        XCTAssertEqual(GpodderSubscriptionAPI.pullPath(.gpodderNet, username: "axel", deviceId: "ios"),
                       GpodderSubscriptionAPI.pushPath(.gpodderNet, username: "axel", deviceId: "ios"))
        XCTAssertNotEqual(GpodderSubscriptionAPI.pullPath(.nextcloud, username: "a", deviceId: "b"),
                          GpodderSubscriptionAPI.pushPath(.nextcloud, username: "a", deviceId: "b"))
    }

    func testPushBodyIsAddRemoveObjectWithRealSlashes() throws {
        let data = try GpodderSubscriptionAPI.pushBody(add: ["https://a.example/feed?x=1"], remove: ["http://b.example/rss"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"add":["https://a.example/feed?x=1"],"remove":["http://b.example/rss"]}"#)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
        XCTAssertEqual(obj?.keys.sorted(), ["add", "remove"])
    }

    func testParsePullBothServers() throws {
        let nc = try GpodderSubscriptionAPI.parsePull(Data(#"{"add":["https://a/f"],"remove":["https://b/f"],"timestamp":1697000123}"#.utf8))
        XCTAssertEqual(nc, SubscriptionDelta(add: ["https://a/f"], remove: ["https://b/f"], timestamp: 1_697_000_123))
        // gpodder.net may add fields; unknown keys are ignored.
        let gp = try GpodderSubscriptionAPI.parsePull(Data(#"{"add":[],"remove":[],"timestamp":12,"extra":true}"#.utf8))
        XCTAssertEqual(gp.timestamp, 12)
        XCTAssertThrowsError(try GpodderSubscriptionAPI.parsePull(Data(#"{"add":[],"remove":[]}"#.utf8)), "timestamp is required")
        XCTAssertThrowsError(try GpodderSubscriptionAPI.parsePull(Data("<html>login</html>".utf8)))
    }

    func testParsePushNextcloudAndGpodderNet() throws {
        XCTAssertEqual(try GpodderSubscriptionAPI.parsePush(Data(#"{"timestamp":99}"#.utf8)), PushResult(timestamp: 99, updateUrls: nil))
        XCTAssertEqual(try GpodderSubscriptionAPI.parsePush(Data()), PushResult(timestamp: nil, updateUrls: nil))
        let gp = try GpodderSubscriptionAPI.parsePush(Data(#"{"timestamp":5,"update_urls":[["http://a/f/","http://a/f"]]}"#.utf8))
        XCTAssertEqual(gp.updateUrls, [["http://a/f/", "http://a/f"]])
    }
}

// MARK: - In-memory servers and a client that runs the app's sync round

/// Nextcloud gpoddersync semantics: raw URLs, last action per URL wins, `since` filters by
/// action time, `timestamp` = server clock. gpodder.net additionally rewrites pushed URLs
/// (`update_urls`, here: strips trailing slashes).
final class FakeSubscriptionServer {
    let flavor: GpodderSubscriptionAPI.Flavor
    private(set) var clock: Int64 = 1000
    private var last: [String: (added: Bool, at: Int64)] = [:]
    private(set) var pushes: [(add: [String], remove: [String])] = []
    var failNextPull = false
    var failNextPush = false

    init(_ flavor: GpodderSubscriptionAPI.Flavor, initial: [String] = []) {
        self.flavor = flavor
        if !initial.isEmpty { record(add: initial, remove: []) }
    }

    /// Another device changes the account.
    func record(add: [String], remove: [String]) {
        clock += 10
        for u in add { last[u] = (true, clock) }
        for u in remove { last[u] = (false, clock) }
    }

    var current: [String] { last.filter { $0.value.added }.map(\.key).sorted() }

    func get(_ url: URL) throws -> Data {
        if failNextPull { failNextPull = false; throw URLError(.timedOut) }
        let since = Int64(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "since" }?.value ?? "") ?? -1
        precondition(since >= 0, "since is required")
        let changed = last.filter { $0.value.at > since }
        let add = changed.filter { $0.value.added }.map(\.key).sorted()
        let remove = since == 0 ? [] : changed.filter { !$0.value.added }.map(\.key).sorted()
        return try JSONSerialization.data(withJSONObject: ["add": add, "remove": remove, "timestamp": clock])
    }

    func post(_ body: Data) throws -> Data {
        if failNextPush { failNextPush = false; throw URLError(.networkConnectionLost) }
        let obj = try JSONSerialization.jsonObject(with: body) as! [String: [String]]
        var add = obj["add"] ?? []
        var rewrites: [[String]] = []
        if flavor == .gpodderNet {
            add = add.map { u in
                var r = u; while r.hasSuffix("/") { r.removeLast() }
                if r != u { rewrites.append([u, r]) }
                return r
            }
        }
        pushes.append((add, obj["remove"] ?? []))
        record(add: add, remove: obj["remove"] ?? [])
        var reply: [String: Any] = ["timestamp": clock]
        if flavor == .gpodderNet { reply["update_urls"] = rewrites }
        return try JSONSerialization.data(withJSONObject: reply)
    }
}

/// Mirrors `GpodderSyncService.syncNow` + `subscribeMissing` + `PodcastStore` merge, using only
/// PodcastCore pieces. A podcast is its URLs (feed URL first, then aliases) plus a load state.
struct FakeClient {
    struct Podcast: Equatable { var urls: [String]; var failed: Bool }
    var library: [Podcast] = []
    var cursor = SubscriptionSyncCursor()
    var fetches: [String] = []

    /// `redirects`: requested URL → final URL. `broken`: fetch fails (placeholder is kept).
    mutating func sync(_ server: FakeSubscriptionServer, redirects: [String: String] = [:], broken: Set<String> = []) throws {
        let base = URL(string: "https://srv.example/")!
        let url = GpodderSubscriptionAPI.pullURL(base: base, flavor: server.flavor, username: "u", deviceId: "d", since: cursor.since)!
        let delta = try GpodderSubscriptionAPI.parsePull(server.get(url))
        var remote = cursor.applyingPull(delta)
        for u in SubscriptionSyncPlan.urlsToImport(remote: delta.add, localFeedURLs: library.flatMap(\.urls)) {
            fetches.append(u)
            var urls = [u]
            if let final = redirects[u] { urls.append(final) }
            let keys = FeedURLEquality.keys(urls)
            if let i = library.firstIndex(where: { !FeedURLEquality.keys($0.urls).isDisjoint(with: keys) }) {
                for x in urls where !FeedURLEquality.keys(library[i].urls).contains(FeedURLEquality.key(x)) { library[i].urls.append(x) }
                library[i].failed = library[i].failed && broken.contains(u)
            } else {
                library.append(Podcast(urls: urls, failed: broken.contains(u)))
            }
        }
        mergeDuplicates()
        if cursor.since > 0 {
            let drop = Set(SubscriptionSyncPlan.podcastsToUnsubscribe(remove: delta.remove, add: delta.add, localPodcasts: library.map(\.urls)))
            library = library.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        }
        let up = SubscriptionSyncPlan.urlsToUpload(localPodcasts: library.map(\.urls), remoteKeys: remote)
        var push: PushResult?
        if !up.isEmpty {
            let result = try GpodderSubscriptionAPI.parsePush(server.post(GpodderSubscriptionAPI.pushBody(add: up, remove: [])))
            remote = SubscriptionSyncCursor.applyingPush(remote, uploaded: up, result: result)
            push = result
        }
        cursor = SubscriptionSyncCursor.committed(pull: delta, keys: remote, push: push)
    }

    mutating func mergeDuplicates() {
        let entries = library.map { FeedDuplicateGrouping.Entry(urls: $0.urls, loaded: !$0.failed) }
        library = FeedDuplicateGrouping.groups(entries.map(\.urls)).map { g in
            let s = FeedDuplicateGrouping.survivor(g, entries: entries)
            var p = library[s]
            for i in g where i != s {
                for x in library[i].urls where !FeedURLEquality.keys(p.urls).contains(FeedURLEquality.key(x)) { p.urls.append(x) }
            }
            return p
        }
    }

    mutating func addLocal(_ url: String) { library.append(Podcast(urls: [url], failed: false)) }
    mutating func unsubscribeLocal(_ url: String) { library.removeAll { FeedURLEquality.keys($0.urls).contains(FeedURLEquality.key(url)) } }

    /// Settings → Reset app data (login kept).
    mutating func resetAppData() { library = []; cursor = .reset; fetches = [] }

    /// One key per podcast (its feed URL), sorted.
    var podcastKeys: [String] { library.map { FeedURLEquality.key($0.urls[0]) }.sorted() }
}

// MARK: - Delta application over several syncs

final class SubscriptionDeltaSyncTests: XCTestCase {
    func run(_ flavor: GpodderSubscriptionAPI.Flavor) throws {
        let server = FakeSubscriptionServer(flavor, initial: ["https://a.example/rss", "https://b.example/rss"])
        var c = FakeClient()

        // 1. since=0: full list imported, local-only feed pushed.
        c.addLocal("https://local.example/rss/")
        try c.sync(server)
        XCTAssertEqual(c.podcastKeys, ["a.example/rss", "b.example/rss", "local.example/rss"], "\(flavor)")
        XCTAssertEqual(server.pushes.count, 1)
        XCTAssertEqual(server.pushes[0].add, ["https://local.example/rss"])
        XCTAssertEqual(c.cursor.since, server.clock, "cursor = push timestamp")
        let afterFirst = c.cursor.since

        // 2. Nothing changed: incremental pull is empty, nothing fetched or pushed.
        let fetched = c.fetches.count
        try c.sync(server)
        XCTAssertEqual(c.fetches.count, fetched)
        XCTAssertEqual(server.pushes.count, 1, "own push is not echoed back as a new upload")
        XCTAssertEqual(c.cursor.since, afterFirst)

        // 3. Another device adds C and removes A: applied exactly once.
        server.record(add: ["https://c.example/rss"], remove: ["https://a.example/rss"])
        try c.sync(server)
        XCTAssertEqual(c.podcastKeys, ["b.example/rss", "c.example/rss", "local.example/rss"])
        XCTAssertEqual(c.fetches.filter { $0.contains("c.example") }.count, 1)
        XCTAssertGreaterThan(c.cursor.since, afterFirst, "timestamp advances on success")
        try c.sync(server)
        XCTAssertEqual(c.fetches.filter { $0.contains("c.example") }.count, 1, "the add is not applied twice")
        XCTAssertFalse(c.cursor.remoteKeys.contains("a.example/rss"))

        // 4. Removed then re-added in one window: kept.
        server.record(add: [], remove: ["https://b.example/rss"])
        server.record(add: ["https://b.example/rss"], remove: [])
        try c.sync(server)
        XCTAssertTrue(c.podcastKeys.contains("b.example/rss"))
    }

    func testNextcloudDeltaOverSeveralSyncs() throws { try run(.nextcloud) }
    func testGpodderNetDeltaOverSeveralSyncs() throws { try run(.gpodderNet) }

    func testFailedPushKeepsCursorAndRetriesSameDelta() throws {
        let server = FakeSubscriptionServer(.nextcloud, initial: ["https://a.example/rss"])
        var c = FakeClient()
        try c.sync(server)
        let before = c.cursor
        server.record(add: ["https://n.example/rss"], remove: [])
        c.addLocal("https://mine.example/rss")
        server.failNextPush = true
        XCTAssertThrowsError(try c.sync(server))
        XCTAssertEqual(c.cursor, before, "no timestamp / known-set change after a failed round")
        try c.sync(server)
        XCTAssertEqual(c.podcastKeys, ["a.example/rss", "mine.example/rss", "n.example/rss"])
        XCTAssertEqual(server.pushes.map(\.add), [["https://mine.example/rss"]], "uploaded once")
        XCTAssertEqual(c.cursor.since, server.clock)
    }

    func testFailedPullKeepsCursor() throws {
        let server = FakeSubscriptionServer(.nextcloud, initial: ["https://a.example/rss"])
        var c = FakeClient()
        try c.sync(server)
        let before = c.cursor
        server.failNextPull = true
        XCTAssertThrowsError(try c.sync(server))
        XCTAssertEqual(c.cursor, before)
    }

    func testGpodderNetUrlRewriteUpdatesKnownSet() {
        let keys = SubscriptionSyncCursor.applyingPush(["x.example/rss"], uploaded: ["https://Up.example/a/"],
                                                       result: PushResult(timestamp: 5, updateUrls: [["https://up.example/a/", "https://cdn.example/a"]]))
        XCTAssertEqual(keys, ["x.example/rss", "cdn.example/a", "up.example/a"])
    }

    func testCommitUsesPullTimestampWithoutPushOrWithoutPushTimestamp() {
        let pull = SubscriptionDelta(add: [], remove: [], timestamp: 40)
        XCTAssertEqual(SubscriptionSyncCursor.committed(pull: pull, keys: [], push: nil).since, 40)
        XCTAssertEqual(SubscriptionSyncCursor.committed(pull: pull, keys: [], push: PushResult(timestamp: nil, updateUrls: nil)).since, 40)
        XCTAssertEqual(SubscriptionSyncCursor.committed(pull: pull, keys: [], push: PushResult(timestamp: 41, updateUrls: nil)).since, 41)
    }

    func testInitialPullReplacesStaleKnownSetIncrementalDoesNot() {
        let delta = SubscriptionDelta(add: ["http://a.example/rss/"], remove: ["https://z.example/rss"], timestamp: 9)
        XCTAssertEqual(SubscriptionSyncCursor(since: 0, remoteKeys: ["stale.example/x"]).applyingPull(delta), ["a.example/rss"])
        XCTAssertEqual(SubscriptionSyncCursor(since: 5, remoteKeys: ["stale.example/x", "z.example/rss"]).applyingPull(delta),
                       ["stale.example/x", "a.example/rss"])
    }
}

// MARK: - Re-pull after Reset app data

final class ResetAppDataRepullTests: XCTestCase {
    /// A long-used, polluted account: variants and redirect aliases of the same podcasts.
    let pollutedAccount = [
        "https://feeds.metaebene.me/lnp/mp3",
        "http://feeds.metaebene.me/lnp/mp3/",
        "https://logbuch-netzpolitik.de/feed/mp3",        // redirects to the line above
        "https://feeds.simplecast.com/54nAGcIl",
        "http://FEEDS.simplecast.com/54nAGcIl/",
        "https://broken.example/rss",                     // 404: must stay as placeholder
        "https://example.org/a.xml",
        "https://example.org/b.xml?token=AbC",
        "ftp://ignored.example/rss",
    ]
    let redirects = ["https://logbuch-netzpolitik.de/feed/mp3": "https://feeds.metaebene.me/lnp/mp3"]
    let broken: Set<String> = ["https://broken.example/rss"]
    let expected = ["broken.example/rss", "example.org/a.xml", "example.org/b.xml?token=AbC",
                    "feeds.metaebene.me/lnp/mp3", "feeds.simplecast.com/54nagcil"]

    func check(_ flavor: GpodderSubscriptionAPI.Flavor) throws {
        let server = FakeSubscriptionServer(flavor, initial: pollutedAccount)
        var c = FakeClient()
        try c.sync(server, redirects: redirects, broken: broken)
        try c.sync(server, redirects: redirects, broken: broken)
        let before = c.podcastKeys
        XCTAssertEqual(before, expected, "\(flavor): complete, no duplicates")
        let serverBefore = server.current
        let pushesBefore = server.pushes.count

        c.resetAppData()
        XCTAssertEqual(c.cursor, SubscriptionSyncCursor(since: 0, remoteKeys: []))
        XCTAssertTrue(c.library.isEmpty)
        try c.sync(server, redirects: redirects, broken: broken)

        XCTAssertEqual(c.podcastKeys, before, "same distinct set after reset")
        XCTAssertEqual(Set(c.podcastKeys).count, c.podcastKeys.count, "no duplicates")
        XCTAssertTrue(c.library.contains { $0.failed && FeedURLEquality.key($0.urls[0]) == "broken.example/rss" }, "failed feed kept")
        XCTAssertEqual(server.pushes.count, pushesBefore, "nothing pushed back")
        XCTAssertEqual(server.current, serverBefore, "server list unchanged")
        let lnp = c.library.first { FeedURLEquality.key($0.urls[0]) == "feeds.metaebene.me/lnp/mp3" }
        XCTAssertTrue(FeedURLEquality.keys(lnp?.urls ?? []).contains("logbuch-netzpolitik.de/feed/mp3"), "alias folded, not a second podcast")

        // A further sync stays stable.
        try c.sync(server, redirects: redirects, broken: broken)
        XCTAssertEqual(c.podcastKeys, before)
        XCTAssertEqual(server.pushes.count, pushesBefore)
    }

    func testNextcloudRepullAfterResetIsIdentical() throws { try check(.nextcloud) }
    func testGpodderNetRepullAfterResetIsIdentical() throws { try check(.gpodderNet) }

    func testResetFromLibraryThatHadLocalOnlyFeedsPushedEarlier() throws {
        // Local-only feeds pushed before the reset are on the server and come back after it.
        let server = FakeSubscriptionServer(.nextcloud, initial: ["https://a.example/rss"])
        var c = FakeClient()
        c.addLocal("http://mine.example/rss/")
        try c.sync(server)
        let before = c.podcastKeys
        let pushes = server.pushes.count
        c.resetAppData()
        try c.sync(server)
        XCTAssertEqual(c.podcastKeys, before)
        XCTAssertEqual(server.pushes.count, pushes)
    }

    func testResetWhileServerChangedMeanwhile() throws {
        let server = FakeSubscriptionServer(.nextcloud, initial: pollutedAccount)
        var c = FakeClient()
        try c.sync(server, redirects: redirects, broken: broken)
        server.record(add: ["https://new.example/rss"], remove: ["https://example.org/a.xml"])
        c.resetAppData()
        try c.sync(server, redirects: redirects, broken: broken)
        XCTAssertEqual(c.podcastKeys, ["broken.example/rss", "example.org/b.xml?token=AbC", "feeds.metaebene.me/lnp/mp3",
                                       "feeds.simplecast.com/54nagcil", "new.example/rss"])
    }
}
