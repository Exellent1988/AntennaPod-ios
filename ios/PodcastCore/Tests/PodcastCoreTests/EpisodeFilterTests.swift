import XCTest
@testable import PodcastCore

final class EpisodeFilterTests: XCTestCase {
    func testEmptyFilterAllowsEverything() {
        XCTAssertTrue(EpisodeFilter.none.isEmpty)
        XCTAssertTrue(EpisodeFilter.none.allows(title: "Anything", durationSeconds: 0))
    }

    func testParseWordsAndQuotedPhrases() {
        XCTAssertEqual(EpisodeFilter.parseTerms(#"news "bonus episode", Trailer"#), ["news", "bonus episode", "trailer"])
    }

    func testIncludeRequiresMatch() {
        let f = EpisodeFilter(includeTerms: "interview")
        XCTAssertTrue(f.allows(title: "Big Interview with X", durationSeconds: 100))
        XCTAssertFalse(f.allows(title: "Weekly news", durationSeconds: 100))
    }

    func testExcludeWinsAndIsDiacriticInsensitive() {
        let f = EpisodeFilter(includeTerms: "folge", excludeTerms: "\"Bonus Müll\"")
        XCTAssertFalse(f.allows(title: "Folge 3 – bonus mull", durationSeconds: 0))
        XCTAssertTrue(f.allows(title: "Folge 3", durationSeconds: 0))
    }

    func testDurationBoundsAndUnknownDurationPasses() {
        let f = EpisodeFilter(minimumDurationSeconds: 600, maximumDurationSeconds: 3600)
        XCTAssertFalse(f.allows(title: "t", durationSeconds: 300))
        XCTAssertTrue(f.allows(title: "t", durationSeconds: 1800))
        XCTAssertFalse(f.allows(title: "t", durationSeconds: 4000))
        XCTAssertTrue(f.allows(title: "t", durationSeconds: 0))
    }

    func testCodableRoundTrip() throws {
        let f = EpisodeFilter(includeTerms: "a", excludeTerms: "b", minimumDurationSeconds: 60, maximumDurationSeconds: 120)
        XCTAssertEqual(try JSONDecoder().decode(EpisodeFilter.self, from: JSONEncoder().encode(f)), f)
    }
}
