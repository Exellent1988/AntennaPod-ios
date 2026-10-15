import XCTest
@testable import PodcastCore

final class AutoDownloadParityTests: XCTestCase {
    func testPowerGate() {
        XCTAssertTrue(AutoDownloadParity.defaultDownloadOnBattery)
        for p in [AutoDownloadParity.PowerState.charging, .full, .unplugged, .unknown] {
            XCTAssertTrue(AutoDownloadParity.powerAllows(downloadOnBattery: true, power: p))
        }
        XCTAssertFalse(AutoDownloadParity.powerAllows(downloadOnBattery: false, power: .unplugged))
        XCTAssertTrue(AutoDownloadParity.powerAllows(downloadOnBattery: false, power: .charging))
        XCTAssertTrue(AutoDownloadParity.powerAllows(downloadOnBattery: false, power: .full))
        XCTAssertTrue(AutoDownloadParity.powerAllows(downloadOnBattery: false, power: .unknown))
    }

    func testCandidatesQueueFirstNoDuplicates() {
        XCTAssertEqual(AutoDownloadParity.candidateOrder(queue: ["q2", "q1", "n1"], newcomers: ["n1", "n2"]),
                       ["q2", "q1", "n1", "n2"])
        XCTAssertEqual(AutoDownloadParity.candidateOrder(queue: [String](), newcomers: ["a", "a"]), ["a"])
    }

    func testFeedURLEdit() {
        let cur = ["https://a.example/rss"]
        XCTAssertEqual(FeedURLEdit.validate(" https://b.example/feed ", currentURLs: cur, otherFeedURLs: []), .ok("https://b.example/feed"))
        XCTAssertEqual(FeedURLEdit.validate("ftp://b.example/feed", currentURLs: cur, otherFeedURLs: []), .invalid)
        XCTAssertEqual(FeedURLEdit.validate("not a url", currentURLs: cur, otherFeedURLs: []), .invalid)
        XCTAssertEqual(FeedURLEdit.validate("https://a.example/rss", currentURLs: cur, otherFeedURLs: []), .unchanged)
        XCTAssertEqual(FeedURLEdit.validate("http://A.example/rss/", currentURLs: cur, otherFeedURLs: []), .ok("http://A.example/rss/"),
                       "same podcast, different spelling is allowed (e.g. https → http)")
        XCTAssertEqual(FeedURLEdit.validate("http://other.example/rss/", currentURLs: cur, otherFeedURLs: ["https://other.example/rss"]), .duplicate)
    }
}
