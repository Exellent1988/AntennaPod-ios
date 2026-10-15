import XCTest
@testable import AntennaPod

/// Redaction for the Settings → Report bug export (Android BugReportActivity port).
final class BugReportRedactorTests: XCTestCase {
    private let R = BugReportRedactor.placeholder
    private func red(_ s: String, _ known: [String] = []) -> String { BugReportRedactor.redact(s, knownSecrets: known) }

    func testURLUserinfo() {
        let out = red("GET https://alice:s3cretPW@gpodder.net/api/2/devices/alice.json failed")
        XCTAssertFalse(out.contains("s3cretPW"))
        XCTAssertFalse(out.contains("alice:"))
        XCTAssertTrue(out.contains("https://\(R)@gpodder.net/api"))
        XCTAssertFalse(red("feed http://user@example.com/rss").contains("user@"))
    }

    func testQueryTokens() {
        let out = red("https://cdn.example.com/ep.mp3?token=abc123XYZ&format=mp3&api_key=K1&Signature=sig999")
        XCTAssertFalse(out.contains("abc123XYZ"))
        XCTAssertFalse(out.contains("K1&"))
        XCTAssertFalse(out.contains("sig999"))
        XCTAssertTrue(out.contains("format=mp3"), "harmless params kept")
        XCTAssertTrue(out.contains("token=\(R)"))
        XCTAssertFalse(red("https://x.io/a?access_token=AT.1-2_3#frag").contains("AT.1-2_3"))
    }

    func testAuthHeadersAndBearer() {
        let out = red("Authorization: Basic YWxpY2U6c2VjcmV0\nCookie: sessionid=deadbeef; csrftoken=x\nHost: gpodder.net")
        XCTAssertFalse(out.contains("YWxpY2U6c2VjcmV0"))
        XCTAssertFalse(out.contains("deadbeef"))
        XCTAssertTrue(out.contains("Host: gpodder.net"))
        XCTAssertFalse(red("headers [\"Authorization\": \"Bearer eyJhbGciOi.payload.sig\"]").contains("eyJhbGciOi"))
        XCTAssertFalse(red("retrying with bearer abcdef0123456789").contains("abcdef0123456789"))
    }

    func testKeyValueAndJSONPasswords() {
        XCTAssertFalse(red("login username=alice password=hunter22 ok").contains("hunter22"))
        XCTAssertFalse(red("login username=alice password=hunter22 ok").contains("alice"))
        XCTAssertFalse(red(#"{"username":"alice","password":"p\"w","device":"ios"}"#).contains("p\\\"w"))
        XCTAssertTrue(red(#"{"username":"alice","password":"pw","device":"ios"}"#).contains(#""device":"ios""#))
        XCTAssertFalse(red("gpodderPassword: topsecret").contains("topsecret"))
        XCTAssertFalse(red("refresh_token=rt-998877").contains("rt-998877"))
    }

    func testKnownGpodderCredentialsAnywhere() {
        let out = red("sync failed for axel-gp at device axel-gp-iphone; pw Tr0ub4dor&3 echoed", ["axel-gp", "Tr0ub4dor&3"])
        XCTAssertFalse(out.contains("axel-gp"))
        XCTAssertFalse(out.contains("Tr0ub4dor"))
        XCTAssertFalse(red("q=Tr0ub4dor%263", ["Tr0ub4dor&3"]).contains("Tr0ub4dor"), "percent-encoded form")
    }

    func testPlainTextUnchanged() {
        let s = "Feed refresh ok: https://feeds.example.com/podcast.xml (12 episodes), keyboard shown"
        XCTAssertEqual(red(s), s)
        XCTAssertEqual(red("short pw", ["ab"]), "short pw", "very short known secrets are ignored")
    }
}
