import XCTest
@testable import AntennaPod

/// Offline, timeout, 401, 500 and redirects for both gpodder.net and Nextcloud (mock URLProtocol only).
final class GpodderResilienceTests: XCTestCase {
    private var session: URLSession!
    private let password = "s3cr3t-pw"

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.requests = []
        MockURLProtocol.handler = nil
    }

    private func client(_ provider: GpodderProvider) throws -> GpodderClient {
        let host = provider == .nextcloud ? "https://cloud.example.com" : "https://gpodder.net"
        var c = try GpodderClient(host: host, username: "axel", password: password, deviceId: "ios_1",
                                  provider: provider, session: session)
        c.retryDelaysNanos = [0, 0]
        return c
    }

    private func call(_ c: GpodderClient) async throws {
        _ = try await c.getSubscriptionChanges(since: 0)
    }

    private func reply(_ code: Int, headers: [String: String] = [:], body: String = #"{"add":[],"remove":[],"timestamp":1}"#) {
        MockURLProtocol.handler = { request in
            var h = ["Content-Type": "application/json"]
            h.merge(headers) { $1 }
            return (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: h)!, Data(body.utf8))
        }
    }

    private func expectError(_ provider: GpodderProvider, file: StaticString = #filePath, line: UInt = #line) async throws -> GpodderError {
        do {
            try await call(try client(provider))
        } catch let e as GpodderError {
            let msg = e.localizedDescription
            XCTAssertFalse(msg.contains(password), msg, file: file, line: line)
            XCTAssertFalse(msg.contains("Basic "), msg, file: file, line: line)
            XCTAssertFalse(msg.isEmpty, file: file, line: line)
            return e
        }
        XCTFail("expected GpodderError", file: file, line: line)
        throw GpodderError.invalidResponse
    }

    private let providers: [GpodderProvider] = [.gpodderNet, .nextcloud]

    // MARK: Offline

    func testOfflineFailsOnceWithClearMessage() async throws {
        for p in providers {
            MockURLProtocol.requests = []
            MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let e = try await expectError(p)
            guard case .network(let u) = e else { return XCTFail("\(p): \(e)") }
            XCTAssertEqual(u.code, .notConnectedToInternet)
            XCTAssertEqual(MockURLProtocol.requests.count, 1, "\(p): offline must not be retried")
            XCTAssertEqual(e.localizedDescription, String(localized: "No internet connection — sync will be retried next time."))
        }
    }

    func testServerDownConnectionRefused() async throws {
        for p in providers {
            MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
            let e = try await expectError(p)
            XCTAssertEqual(e.localizedDescription,
                           String(localized: "Sync server is offline or refuses the connection — check the host URL or try again later."))
        }
    }

    // MARK: Timeout

    func testTimeoutRetriedThreeTimesThenClearMessage() async throws {
        for p in providers {
            MockURLProtocol.requests = []
            MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
            let e = try await expectError(p)
            XCTAssertEqual(MockURLProtocol.requests.count, 3, "\(p)")
            XCTAssertEqual(e.localizedDescription,
                           String(localized: "Sync server did not respond in time (timeout) — tried 3 times, try again later."))
        }
    }

    func testRequestsHaveFiniteTimeout() async throws {
        reply(200)
        try await call(try client(.nextcloud))
        let t = try XCTUnwrap(MockURLProtocol.requests.first?.timeoutInterval)
        XCTAssertTrue(t > 0 && t <= 60, "\(t)")
    }

    // MARK: 401

    func testUnauthorizedPerProviderNotRetried() async throws {
        MockURLProtocol.requests = []
        reply(401, body: "")
        var e = try await expectError(.gpodderNet)
        guard case .unauthorized = e else { return XCTFail("\(e)") }
        XCTAssertTrue(e.localizedDescription.contains("401"))
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        MockURLProtocol.requests = []
        e = try await expectError(.nextcloud)
        guard case .nextcloudAuth(401) = e else { return XCTFail("\(e)") }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    // MARK: 500

    func testServerError500RetriedThenReported() async throws {
        for p in providers {
            MockURLProtocol.requests = []
            reply(500, body: "Internal error: user=axel password=\(password)")
            let e = try await expectError(p)
            guard case .serverError(500) = e else { return XCTFail("\(p): \(e)") }
            XCTAssertEqual(MockURLProtocol.requests.count, 3)
            XCTAssertTrue(e.localizedDescription.contains("500"))
        }
    }

    func testUnexpectedStatusDoesNotEchoServerBody() async throws {
        reply(418, body: "echo Authorization: Basic \(password)")
        let e = try await expectError(.gpodderNet)
        guard case .httpStatus(418, _) = e else { return XCTFail("\(e)") }
    }

    // MARK: Redirects

    func testSameHostHTTPSRedirectFollowedWithAuth() async throws {
        for p in providers {
            MockURLProtocol.requests = []
            MockURLProtocol.handler = { request in
                if MockURLProtocol.requests.count == 1 {
                    return (HTTPURLResponse(url: request.url!, statusCode: 301, httpVersion: nil,
                                            headerFields: ["Location": request.url!.path + "?moved=1"])!, Data())
                }
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                        headerFields: ["Content-Type": "application/json"])!,
                        Data(#"{"add":["https://a/f"],"remove":[],"timestamp":2}"#.utf8))
            }
            let changes = try await try client(p).getSubscriptionChanges(since: 0)
            XCTAssertEqual(changes.add, ["https://a/f"], "\(p)")
            XCTAssertEqual(MockURLProtocol.requests.count, 2)
            let second = MockURLProtocol.requests[1]
            XCTAssertEqual(second.url?.query, "moved=1")
            XCTAssertEqual(second.url?.scheme, "https")
            XCTAssertNotNil(second.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testRedirectToHTTPStopsWithoutSendingCredentials() async throws {
        for p in providers {
            MockURLProtocol.requests = []
            MockURLProtocol.handler = { request in
                var c = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                c.scheme = "http"
                return (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                        headerFields: ["Location": c.url!.absoluteString])!, Data())
            }
            let e = try await expectError(p)
            guard case .insecureRedirect = e else { return XCTFail("\(p): \(e)") }
            XCTAssertEqual(MockURLProtocol.requests.count, 1, "no request may go to http")
        }
    }

    func testRedirectToOtherHostStopsWithoutSendingCredentials() async throws {
        for p in providers {
            MockURLProtocol.requests = []
            reply(307, headers: ["Location": "https://evil.example.org/steal"])
            let e = try await expectError(p)
            guard case .redirectedToOtherHost(let host) = e else { return XCTFail("\(p): \(e)") }
            XCTAssertEqual(host, "evil.example.org")
            XCTAssertTrue(e.localizedDescription.contains("evil.example.org"))
            XCTAssertEqual(MockURLProtocol.requests.count, 1)
        }
    }

    func testRedirectToLoginPageDetected() async throws {
        reply(302, headers: ["Location": "/index.php/login?redirect_url=x"])
        let e = try await expectError(.nextcloud)
        guard case .redirectedToLogin = e else { return XCTFail("\(e)") }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testRedirectLoopStops() async throws {
        MockURLProtocol.requests = []
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                             headerFields: ["Location": request.url!.path + "?n=\(MockURLProtocol.requests.count)"])!, Data())
        }
        let e = try await expectError(.gpodderNet)
        guard case .tooManyRedirects = e else { return XCTFail("\(e)") }
        XCTAssertEqual(MockURLProtocol.requests.count, GpodderClient.maxRedirects + 1)
    }

    func testPostRedirect303BecomesGet() throws {
        var req = URLRequest(url: URL(string: "https://gpodder.net/api/2/x.json")!)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 303, httpVersion: nil, headerFields: ["Location": "/api/2/y.json"])!
        let next = try GpodderClient.redirectedRequest(from: req, response: resp, hops: 0)
        XCTAssertEqual(next.httpMethod, "GET")
        XCTAssertNil(next.httpBody)
        XCTAssertEqual(next.url?.absoluteString, "https://gpodder.net/api/2/y.json")
    }

    // MARK: German copy

    func testGermanTranslationsExist() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let de = try XCTUnwrap(Bundle(path: path))
        let keys = [
            "No internet connection — sync will be retried next time.",
            "Sync server is offline or refuses the connection — check the host URL or try again later.",
            "Sync server did not respond in time (timeout) — tried 3 times, try again later.",
            "Connection to the sync server was lost — try again.",
            "gpodder.net rejected the login (HTTP 401) — check the username and password.",
            "Sync server error (HTTP %lld) — tried 3 times, try again later.",
            "The sync server redirected to an insecure (http) address — stopped to protect your password. Check the server URL.",
            "The sync server redirected to another server (%@) — stopped to protect your password. Enter that address directly if it is correct.",
            "Too many redirects from the sync server — check the server URL.",
            "Network error while syncing (code %lld)",
        ]
        for k in keys {
            let v = de.localizedString(forKey: k, value: "<missing>", table: nil)
            XCTAssertNotEqual(v, "<missing>", k)
            XCTAssertNotEqual(v, k, "untranslated: \(k)")
        }
    }
}
