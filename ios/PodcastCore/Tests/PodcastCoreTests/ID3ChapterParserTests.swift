import XCTest
@testable import PodcastCore

final class ID3ChapterParserTests: XCTestCase {
    private let two = [
        ID3ChapterTagBuilder.Input(title: "Intro", startMs: 0, endMs: 61_500),
        ID3ChapterTagBuilder.Input(title: "Hauptteil – Ä", startMs: 61_500, endMs: 300_000, url: "https://example.org/x"),
    ]

    func testParsesV23() {
        let c = ID3ChapterParser.chapters(in: ID3ChapterTagBuilder.tag(two, version: 3))
        XCTAssertEqual(c.map(\.title), ["Intro", "Hauptteil – Ä"])
        XCTAssertEqual(c.map(\.startSeconds), [0, 61.5])
        XCTAssertEqual(c[1].url, "https://example.org/x")
        XCTAssertNil(c[0].url)
    }

    func testParsesV24Synchsafe() {
        let c = ID3ChapterParser.chapters(in: ID3ChapterTagBuilder.tag(two, version: 4))
        XCTAssertEqual(c.map(\.startSeconds), [0, 61.5])
    }

    func testUTF16AndLatin1Titles() {
        XCTAssertEqual(ID3ChapterParser.chapters(in: ID3ChapterTagBuilder.tag(two, titleEncoding: 1)).map(\.title), ["Intro", "Hauptteil – Ä"])
        let latin = [ID3ChapterTagBuilder.Input(title: "Größe", startMs: 0, endMs: 1)]
        XCTAssertEqual(ID3ChapterParser.chapters(in: ID3ChapterTagBuilder.tag(latin, titleEncoding: 0)).first?.title, "Größe")
    }

    func testEmbeddedImage() {
        let img = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let c = ID3ChapterParser.chapters(in: ID3ChapterTagBuilder.tag([.init(title: "A", startMs: 0, endMs: 1, image: img)]))
        XCTAssertEqual(c.first?.imageData, img)
        XCTAssertEqual(c.first?.imageMimeType, "image/png")
    }

    func testSortsAndDedupes() {
        let input = [ID3ChapterTagBuilder.Input(title: "B", startMs: 5000, endMs: 6000),
                     ID3ChapterTagBuilder.Input(title: "A", startMs: 0, endMs: 5000),
                     ID3ChapterTagBuilder.Input(title: "B2", startMs: 5000, endMs: 6000)]
        XCTAssertEqual(ID3ChapterParser.chapters(in: ID3ChapterTagBuilder.tag(input)).map(\.title), ["A", "B"])
    }

    func testNonID3AndTruncatedInputs() {
        XCTAssertEqual(ID3ChapterParser.chapters(in: Data("RIFF....".utf8)), [])
        XCTAssertEqual(ID3ChapterParser.chapters(in: Data()), [])
        let full = ID3ChapterTagBuilder.tag(two)
        for n in stride(from: 0, to: full.count, by: 7) { _ = ID3ChapterParser.chapters(in: full.prefix(n)) } // no crash
        XCTAssertNil(ID3ChapterParser.tagLength(header: Data([0x49, 0x44, 0x33, 2, 0, 0, 0, 0, 0, 0])))
    }

    func testTagLength() {
        let tag = ID3ChapterTagBuilder.tag(two)
        XCTAssertEqual(ID3ChapterParser.tagLength(header: tag), tag.count)
    }

    func testNowPlayingIndex() {
        let s: [Double] = [0, 60, 120]
        XCTAssertEqual(ChapterNowPlaying.index(starts: s, at: 0), 0)
        XCTAssertEqual(ChapterNowPlaying.index(starts: s, at: 59.9), 0)
        XCTAssertEqual(ChapterNowPlaying.index(starts: s, at: 60), 1)
        XCTAssertEqual(ChapterNowPlaying.index(starts: s, at: 500), 2)
        XCTAssertNil(ChapterNowPlaying.index(starts: [10], at: 5))
        XCTAssertNil(ChapterNowPlaying.index(starts: [], at: 5))
    }
}
