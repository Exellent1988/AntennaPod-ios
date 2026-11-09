import PodcastCore
import XCTest
@testable import AntennaPod

/// Player details parity: show-notes timestamps seek, link attributes, share extras.
@MainActor
final class PlayerDetailsTests: PlaybackFixtureTestCase {
    func testTimestampSeeksOnlyCurrentEpisode() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 5) { self.playback.isPlaying }
        XCTAssertFalse(ShowNotesText.seek(to: 5, episode: episodes[1], playback: playback), "other episode → hint, no seek")
        XCTAssertTrue(ShowNotesText.seek(to: 2, episode: episodes[0], playback: playback))
        try await waitFor("seeked", timeout: 5) { abs(self.playback.positionSeconds - 2) < 1.5 }
    }

    func testAttributedLinks() {
        let s = ShowNotesText.attributed("Go 01:05 https://a.org now", anchors: [], duration: 0)
        let links = s.runs.compactMap(\.link)
        XCTAssertEqual(links.map(\.absoluteString), ["antennapod-seek:65", "https://a.org"])
        XCTAssertEqual(ShowNotesText.seekSeconds(from: links[0]), 65)
        XCTAssertNil(ShowNotesText.seekSeconds(from: links[1]))
        XCTAssertEqual(String(s.characters), "Go 01:05 https://a.org now")
    }

    func testShareFeedURLOnlyHttp() {
        let url = "https://share-extras.example/feed"
        let f = PodcastFeed(id: UUID(), title: "S", feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
                            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
                            lockedOwner: nil, podcastGuid: nil,
                            episodes: [PodcastEpisode(id: "\(url)#e", title: "e", downloadUrl: "https://e/e.mp3", mimeType: "audio/mpeg", durationSeconds: 60)])
        store.feeds = [f]
        XCTAssertEqual(PlayerShareExtras.feedURL(for: f.episodes[0], store: store)?.absoluteString, url)
        var local = f; local.feedUrl = "local-folder://x"
        store.feeds = [local]
        XCTAssertNil(PlayerShareExtras.feedURL(for: f.episodes[0], store: store), "non-http feed → no share")
    }
}
