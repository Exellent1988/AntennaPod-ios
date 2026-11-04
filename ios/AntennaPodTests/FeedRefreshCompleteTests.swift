import XCTest
@testable import AntennaPod

final class FeedRefreshCompleteTests: XCTestCase {
    private let url = URL(string: "https://example.com/feed.xml")!

    func testNormalRefreshUsesDefaultCachePolicy() {
        let r = FeedRepository.feedRequest(url: url, credentials: nil, ignoreCache: false)
        XCTAssertEqual(r.cachePolicy, .useProtocolCachePolicy)
        XCTAssertNil(r.value(forHTTPHeaderField: "Cache-Control"))
    }

    func testRefreshCompleteBypassesCaches() {
        let r = FeedRepository.feedRequest(url: url, credentials: nil, ignoreCache: true)
        XCTAssertEqual(r.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertNotNil(r.value(forHTTPHeaderField: "Accept"))
    }
}
