import XCTest
@testable import PodcastCore

final class ShowNotesLinksTests: XCTestCase {
    func testTimestamps() {
        XCTAssertEqual(ShowNotesLinks.timestampSeconds("1:02:03"), 3723)
        XCTAssertEqual(ShowNotesLinks.timestampSeconds("12:30"), 750)
        XCTAssertEqual(ShowNotesLinks.timestampSeconds("75:00"), 4500, "mm may exceed 59 without hours")
        XCTAssertNil(ShowNotesLinks.timestampSeconds("1:61:00"))
        XCTAssertNil(ShowNotesLinks.timestampSeconds("12:75"))
        let runs = ShowNotesLinks.runs("00:00 Intro, 12:30 Topic, 2:00:00 end, v1.2:3", durationSeconds: 3600)
        XCTAssertEqual(runs.compactMap(\.kind), [.timestamp(seconds: 0), .timestamp(seconds: 750)], "beyond duration ignored")
    }

    func testLinksAndAnchors() {
        let html = #"<p>See <a href="https://example.com/x?a=1&amp;b=2">our site</a> and https://foo.org/page.</p>"#
        let a = ShowNotesLinks.anchors(inHTML: html)
        XCTAssertEqual(a.first?.href, "https://example.com/x?a=1&b=2")
        let runs = ShowNotesLinks.runs("See our site and https://foo.org/page. At 1:00", anchors: a)
        XCTAssertEqual(runs.map(\.text).joined(), "See our site and https://foo.org/page. At 1:00")
        XCTAssertEqual(runs.compactMap(\.kind), [.url("https://example.com/x?a=1&b=2"), .url("https://foo.org/page"), .timestamp(seconds: 60)])
        XCTAssertTrue(ShowNotesLinks.anchors(inHTML: #"<a href="mailto:x@y">mail me</a>"#).isEmpty)
    }

    func testOverlapUrlWins() {
        let runs = ShowNotesLinks.runs("https://x.org/t=10:20 ok")
        XCTAssertEqual(runs.compactMap(\.kind), [.url("https://x.org/t=10:20")])
    }
}
