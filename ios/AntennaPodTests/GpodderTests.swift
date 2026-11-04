import XCTest
@testable import AntennaPod

/// Records requests and answers from a per-test handler.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class GpodderClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.requests = []
        MockURLProtocol.handler = nil
    }

    private func respond(_ status: Int = 200, json: String, contentType: String = "application/json") {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )!
            return (response, Data(json.utf8))
        }
    }

    private func client(_ provider: GpodderProvider, host: String) throws -> GpodderClient {
        try GpodderClient(host: host, username: "axel", password: "secret", deviceId: "ios_1",
                          provider: provider, session: session)
    }

    // MARK: Endpoints

    func testGpodderNetSubscriptionEndpointAndAuth() async throws {
        respond(json: #"{"add":["https://a.example/feed"],"remove":[],"timestamp":42}"#)
        let changes = try await client(.gpodderNet, host: "gpodder.net").getSubscriptionChanges(since: 0)
        XCTAssertEqual(changes.add, ["https://a.example/feed"])
        XCTAssertEqual(changes.timestamp, 42)
        let req = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://gpodder.net/api/2/subscriptions/axel/ios_1.json?since=0")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("axel:secret".utf8).base64EncodedString())
    }

    func testNextcloudServerRootGetsAppPath() async throws {
        respond(json: #"{"add":[],"remove":[],"timestamp":1}"#)
        _ = try await client(.nextcloud, host: "cloud.example.com").getSubscriptionChanges(since: 5)
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.absoluteString,
                       "https://cloud.example.com/index.php/apps/gpoddersync/subscriptions?since=5")
    }

    func testNextcloudSubfolderAndFullPath() {
        XCTAssertEqual(GpodderClient.normalizeBaseURL("https://h.example/nc", provider: .nextcloud)?.absoluteString,
                       "https://h.example/nc/index.php/apps/gpoddersync/")
        XCTAssertEqual(GpodderClient.normalizeBaseURL("https://h.example/index.php/apps/gpoddersync", provider: .nextcloud)?.absoluteString,
                       "https://h.example/index.php/apps/gpoddersync/")
        XCTAssertEqual(GpodderClient.normalizeBaseURL("https://opodsync.example/", provider: .gpodderNet)?.absoluteString,
                       "https://opodsync.example/")
    }

    func testNextcloudEpisodeActionEndpoints() async throws {
        respond(json: #"{"actions":[],"timestamp":9}"#)
        let c = try client(.nextcloud, host: "https://cloud.example.com")
        _ = try await c.getEpisodeActions(since: 3)
        XCTAssertEqual(MockURLProtocol.requests.last?.url?.absoluteString,
                       "https://cloud.example.com/index.php/apps/gpoddersync/episode_action?since=3")
        respond(json: #"{"timestamp":10}"#)
        let ts = try await c.uploadEpisodeActions([GpodderEpisodeAction(
            podcast: "https://a/feed", episode: "https://a/1.mp3", action: "play",
            timestamp: "2026-10-14T20:00:00", started: 0, position: 10, total: 100)])
        XCTAssertEqual(ts, 10)
        XCTAssertEqual(MockURLProtocol.requests.last?.url?.absoluteString,
                       "https://cloud.example.com/index.php/apps/gpoddersync/episode_action/create")
        XCTAssertEqual(MockURLProtocol.requests.last?.httpMethod, "POST")
    }

    func testGpodderNetEpisodeActionsAggregated() async throws {
        respond(json: #"{"actions":[{"podcast":"https://a/feed","episode":"https://a/1.mp3","action":"play","timestamp":"2026-10-14T20:00:00","started":0,"position":30,"total":600,"device":"x"}],"timestamp":77}"#)
        let changes = try await client(.gpodderNet, host: "https://gpodder.net").getEpisodeActions(since: 0)
        XCTAssertEqual(changes.actions.first?.position, 30)
        XCTAssertNotNil(changes.actions.first?.date)
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.absoluteString,
                       "https://gpodder.net/api/2/episodes/axel.json?since=0&aggregated=true")
    }

    // MARK: Parsing

    func testDeviceListParsing() async throws {
        respond(json: #"[{"id":"phone","caption":"Phone","type":"mobile","subscriptions":12},{"id":"pc"}]"#)
        let devices = try await client(.gpodderNet, host: "https://gpodder.net").listDevices()
        XCTAssertEqual(devices.map(\.id), ["phone", "pc"])
        XCTAssertEqual(devices.first?.subscriptions, 12)
        XCTAssertEqual(devices.last?.caption, "")
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, "/api/2/devices/axel.json")
    }

    func testNextcloudHasNoDevices() async throws {
        let devices = try await client(.nextcloud, host: "https://c.example").listDevices()
        XCTAssertTrue(devices.isEmpty)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testAllSubscriptionsAcceptsObjectsAndStrings() throws {
        XCTAssertEqual(try GpodderClient.parseSubscriptionList(Data(#"[{"url":"https://a/f","title":"A"}]"#.utf8)), ["https://a/f"])
        XCTAssertEqual(try GpodderClient.parseSubscriptionList(Data(#"["https://b/f"]"#.utf8)), ["https://b/f"])
        XCTAssertThrowsError(try GpodderClient.parseSubscriptionList(Data("<html>".utf8)))
    }

    func testAllSubscriptionsGpodderNetPath() async throws {
        respond(json: #"[{"url":"https://a/f"}]"#)
        let urls = try await client(.gpodderNet, host: "https://gpodder.net").getAllSubscriptionURLs()
        XCTAssertEqual(urls, ["https://a/f"])
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.absoluteString, "https://gpodder.net/subscriptions/axel.json")
    }

    // MARK: Errors

    func testUnauthorized() async throws {
        respond(401, json: "")
        do {
            try await client(.gpodderNet, host: "https://gpodder.net").login()
            XCTFail("expected error")
        } catch GpodderError.unauthorized {
        } catch { XCTFail("\(error)") }
    }

    func testHTMLLoginPageIsReported() async throws {
        respond(json: "<html>login</html>", contentType: "text/html; charset=utf-8")
        do {
            _ = try await client(.nextcloud, host: "https://c.example").getSubscriptionChanges(since: 0)
            XCTFail("expected error")
        } catch GpodderError.htmlInsteadOfJSON {
        } catch { XCTFail("\(error)") }
    }

    func testNetworkErrorMapped() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.cannotFindHost) }
        do {
            try await client(.gpodderNet, host: "https://nope.invalid").login()
            XCTFail("expected error")
        } catch GpodderError.network(let e) {
            XCTAssertEqual(e.code, .cannotFindHost)
        } catch { XCTFail("\(error)") }
    }
}

final class GpodderSyncLogicTests: XCTestCase {
    func testImportDedupesAgainstLocalAndWithinList() {
        let todo = GpodderSyncLogic.urlsToImport(
            remote: ["https://A.example/feed/", "https://a.example/feed", "https://b.example/Feed?t=X",
                     "https://b.example/feed?t=x", "ftp://c/feed", "", "https://local.example/rss"],
            localFeedURLs: ["https://LOCAL.example/rss/"]
        )
        XCTAssertEqual(todo, ["https://A.example/feed", "https://b.example/Feed?t=X"])
    }

    func testRemoteUpdateNewerWinsAndPlayedDetection() {
        let refs = [
            GpodderSyncLogic.EpisodeRef(episodeId: "e1", feedUrl: "https://a/feed", mediaUrl: "https://a/1.mp3"),
            GpodderSyncLogic.EpisodeRef(episodeId: "e2", feedUrl: "https://a/feed", mediaUrl: "https://a/2.mp3"),
        ]
        let t = GpodderEpisodeAction.parseTimestamp("2026-10-14T20:00:00")!
        let ms = Int64(t.timeIntervalSince1970 * 1000)
        let local: [String: EpisodePlaybackState] = [
            "e2": EpisodePlaybackState(positionSeconds: 5, durationSeconds: 100, isPlayed: false, updatedAtEpochMs: ms + 1),
        ]
        let actions = [
            GpodderEpisodeAction(podcast: "https://a/feed", episode: "https://a/1.mp3", action: "play",
                                 timestamp: "2026-10-14T19:00:00", started: 0, position: 10, total: 100),
            GpodderEpisodeAction(podcast: "https://a/feed", episode: "https://A/1.mp3/", action: "play",
                                 timestamp: "2026-10-14T20:00:00", started: 0, position: 98, total: 100),
            GpodderEpisodeAction(podcast: "https://a/feed", episode: "https://a/2.mp3", action: "play",
                                 timestamp: "2026-10-14T20:00:00", started: 0, position: 50, total: 100),
            GpodderEpisodeAction(podcast: "https://a/feed", episode: "https://a/1.mp3", action: "download",
                                 timestamp: "2026-10-14T21:00:00"),
        ]
        let updates = GpodderSyncLogic.remoteUpdates(actions: actions, refs: refs, localStates: local)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.episodeId, "e1")
        XCTAssertEqual(updates.first?.isPlayed, true)
        XCTAssertEqual(updates.first?.updatedAtEpochMs, ms)
    }

    func testLocalActionsSinceCursor() {
        let refs = [
            GpodderSyncLogic.EpisodeRef(episodeId: "e1", feedUrl: "https://a/feed", mediaUrl: "https://a/1.mp3"),
            GpodderSyncLogic.EpisodeRef(episodeId: "e2", feedUrl: "https://a/feed", mediaUrl: "https://a/2.mp3"),
            GpodderSyncLogic.EpisodeRef(episodeId: "e3", feedUrl: "https://a/feed", mediaUrl: "https://a/3.mp3"),
        ]
        let states: [String: EpisodePlaybackState] = [
            "e1": EpisodePlaybackState(positionSeconds: 0, durationSeconds: 300, isPlayed: true, updatedAtEpochMs: 2000),
            "e2": EpisodePlaybackState(positionSeconds: 40, durationSeconds: 300, isPlayed: false, updatedAtEpochMs: 500),
            "e3": EpisodePlaybackState(positionSeconds: 40, durationSeconds: 0, isPlayed: false, updatedAtEpochMs: 2000),
        ]
        let out = GpodderSyncLogic.localActions(refs: refs, localStates: states, sinceMs: 1000, deviceId: "ios_1")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.episode, "https://a/1.mp3")
        XCTAssertEqual(out.first?.position, 300)
        XCTAssertEqual(out.first?.total, 300)
        XCTAssertEqual(out.first?.device, "ios_1")
        XCTAssertEqual(out.first?.timestamp, "1970-01-01T00:00:02")
    }

    func testTimestampParsingVariants() {
        XCTAssertNotNil(GpodderEpisodeAction.parseTimestamp("2026-10-14T20:00:00Z"))
        XCTAssertNotNil(GpodderEpisodeAction.parseTimestamp("2026-10-14T20:00:00.123"))
        XCTAssertNil(GpodderEpisodeAction.parseTimestamp("yesterday"))
    }
}
