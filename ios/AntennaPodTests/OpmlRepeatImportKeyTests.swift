import XCTest
@testable import AntennaPod

/// OPML import dedupe lives in the app (PodcastStore.importOpml, key =
/// FeedURLNormalization.canonicalKey lowercased), not in PodcastCore. A second import of the
/// same file skips every outline whose key is already subscribed; these pin the spellings
/// that collapse to one key. (Unbuilt on Linux; app target only.)
final class OpmlRepeatImportKeyTests: XCTestCase {
    private func key(_ s: String) -> String { FeedURLNormalization.canonicalKey(s).lowercased() }

    func testSpellingVariantsShareOneKey() {
        let base = key("https://a.example/feed")
        for v in ["http://a.example/feed", "https://A.example/feed/", "  https://a.example/Feed  "] {
            XCTAssertEqual(key(v), base, v)
        }
    }

    func testDifferentQueriesStayDistinct() {
        XCTAssertNotEqual(key("https://b.example/rss?x=1"), key("https://b.example/rss?x=2"))
    }
}
