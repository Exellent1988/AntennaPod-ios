import MediaPlayer
import PodcastCore
import XCTest
@testable import AntennaPod

/// ID3v2 CHAP chapters from a local MP3 (Android ChapterReader parity) and chapter fields in the
/// Now Playing info, with a real AVPlayer fixture.
@MainActor
final class ChaptersParityTests: PlaybackFixtureTestCase {

    private func writeTempFile(_ data: Data, ext: String = "mp3") throws -> URL {
        let url = fixtureDir.appendingPathComponent("chap-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }

    func testReaderReturnsID3ChaptersFromLocalMP3() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var file = ID3ChapterTagBuilder.tag([
            .init(title: "Begrüßung", startMs: 0, endMs: 30_000),
            .init(title: "Thema", startMs: 30_000, endMs: 90_000, url: "https://example.org/thema", image: png),
        ])
        file.append(Data(repeating: 0xFF, count: 512)) // stand-in audio frames
        let url = try writeTempFile(file)

        let chapters = await MediaFileChapterReader.chapters(fromFileURL: url)
        XCTAssertEqual(chapters.map(\.title), ["Begrüßung", "Thema"])
        XCTAssertEqual(chapters.map(\.startTimeSeconds), [0, 30])
        XCTAssertEqual(chapters[1].displayLinkURL?.absoluteString, "https://example.org/thema")
        let image = try XCTUnwrap(chapters[1].displayImageURL, "embedded APIC image is shown")
        XCTAssertTrue(image.isFileURL)
        XCTAssertEqual(try Data(contentsOf: image), png)
        XCTAssertNil(chapters[0].displayImageURL)
        try? FileManager.default.removeItem(at: image)
    }

    func testReaderWithoutID3FallsBackToAVFoundation() async throws {
        let url = try writeTempFile(Data(repeating: 0, count: 64), ext: "m4a")
        let chapters = await MediaFileChapterReader.chapters(fromFileURL: url)
        XCTAssertEqual(chapters, [])
    }

    func testFileImageOutsideChapterCacheIsNotShown() {
        let c = PodcastChapter(title: "x", startTimeSeconds: 0, imageUrl: "file:///etc/passwd")
        XCTAssertNil(c.displayImageURL)
    }

    func testNowPlayingChapterFieldsHelper() {
        let chapters = [PodcastChapter(title: "B", startTimeSeconds: 60), PodcastChapter(title: "A", startTimeSeconds: 0)]
        XCTAssertEqual(PlaybackService.nowPlayingChapterFields(chapters: chapters, at: 10)?.title, "A")
        let f = PlaybackService.nowPlayingChapterFields(chapters: chapters, at: 61)
        XCTAssertEqual(f?.index, 1); XCTAssertEqual(f?.count, 2); XCTAssertEqual(f?.title, "B")
        XCTAssertNil(PlaybackService.nowPlayingChapterFields(chapters: [], at: 1))
    }

    func testNowPlayingFollowsChapterDuringPlayback() async throws {
        var ep = episodes[0]
        ep.chapters = [PodcastChapter(title: "Kapitel A", startTimeSeconds: 0),
                       PodcastChapter(title: "Kapitel B", startTimeSeconds: 1.2)]
        store.queue = [ep] + Array(episodes.dropFirst())
        XCTAssertTrue(playback.play(episode: ep))
        try await waitFor("chapter A in Now Playing", timeout: 5) {
            self.playback.lastNowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String == "Kapitel A"
        }
        XCTAssertEqual(playback.lastNowPlayingInfo?[MPNowPlayingInfoPropertyChapterCount] as? Int, 2)
        try await waitFor("chapter B in Now Playing", timeout: 6) {
            self.playback.lastNowPlayingInfo?[MPNowPlayingInfoPropertyChapterNumber] as? Int == 1
        }
        XCTAssertEqual(playback.lastNowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String, "Kapitel B")
        XCTAssertEqual(playback.lastNowPlayingInfo?[MPMediaItemPropertyTitle] as? String, ep.title)
    }

    func testNowPlayingWithoutChaptersKeepsFeedLine() async throws {
        XCTAssertTrue(playback.play(episode: episodes[1]))
        try await waitFor("now playing", timeout: 5) { self.playback.lastNowPlayingInfo != nil }
        XCTAssertNil(playback.lastNowPlayingInfo?[MPNowPlayingInfoPropertyChapterCount])
    }
}
