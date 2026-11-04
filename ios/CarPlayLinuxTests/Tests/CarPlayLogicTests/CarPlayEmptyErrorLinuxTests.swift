import XCTest
@testable import CarPlayLogic

/// Android Auto `loadChildrenSynchronous` empty / media-less parity.
@MainActor
final class CarPlayEmptyErrorLinuxTests: XCTestCase {
    func builder(_ s: PodcastStore, current: PodcastEpisode? = nil, dl: DownloadService? = nil) -> CarPlayListBuilder {
        CarPlayListBuilder(store: s, downloads: dl, settings: AppSettings(), currentEpisode: current, limit: 100)
    }

    func testHasMedia() {
        XCTAssertTrue(CarPlayParity.hasMedia(downloadUrl: "https://e/x.mp3", isDownloaded: false))
        XCTAssertTrue(CarPlayParity.hasMedia(downloadUrl: nil, isDownloaded: true))
        XCTAssertFalse(CarPlayParity.hasMedia(downloadUrl: nil, isDownloaded: false))
        XCTAssertFalse(CarPlayParity.hasMedia(downloadUrl: "  ", isDownloaded: false))
    }

    func testMedialessEpisodesAreSkippedInEveryList() {
        let s = PodcastStore()
        var noMedia = PodcastEpisode(id: "nm", title: "No media"); noMedia.downloadUrl = nil
        let ok = PodcastEpisode(id: "ok", title: "OK")
        let f = PodcastFeed(title: "F", feedUrl: "https://f/", episodes: [noMedia, ok])
        s.feeds = [f]; s.queue = [noMedia, ok]
        let b = builder(s)
        XCTAssertEqual(b.allEpisodeInfos().map(\.id), ["ok"])
        XCTAssertEqual(b.episodeRows(b.allEpisodeInfos()).map(\.title), ["OK"])
        XCTAssertEqual(b.feedEpisodeRows(f.id).map(\.title), ["OK"])
        XCTAssertEqual(b.queueSections().last?.1.map(\.title), ["OK"])
        XCTAssertEqual(b.upNextRows().map(\.title), ["OK"])
        XCTAssertEqual(b.subscriptionRows().count, 1, "Feed still listed")
    }

    func testDownloadedWithoutRemoteURLStillListed() {
        let s = PodcastStore()
        var local = PodcastEpisode(id: "loc", title: "Local"); local.downloadUrl = nil
        s.feeds = [PodcastFeed(title: "F", feedUrl: "https://f/", episodes: [local])]
        let dl = DownloadService(); dl.downloads = [DownloadedEpisode(id: "loc", downloadedAtEpochMs: 1)]
        let b = builder(s, dl: dl)
        XCTAssertEqual(b.downloadRows(b.allEpisodeInfos()).map(\.title), ["Local"])
    }

    func testEmptyLibraryBuildsEmptyListsWithoutCrash() {
        let b = builder(PodcastStore())
        XCTAssertTrue(b.allEpisodeInfos().isEmpty)
        XCTAssertTrue(b.episodeRows([]).isEmpty)
        XCTAssertTrue(b.downloadRows([]).isEmpty)
        XCTAssertTrue(b.subscriptionRows().isEmpty)
        XCTAssertTrue(b.upNextRows().isEmpty)
        let q = b.queueSections()
        XCTAssertEqual(q.count, 1); XCTAssertNil(q[0].0); XCTAssertTrue(q[0].1.isEmpty)
        XCTAssertNil(b.episodeToPlay(id: "x", feedId: nil))
    }

    func testOfflineNothingDownloadedGivesEmptyDownloadsButStreamableEpisodes() {
        let s = PodcastStore()
        s.feeds = [PodcastFeed(title: "F", feedUrl: "https://f/", episodes: [PodcastEpisode(id: "a", title: "A")])]
        let b = builder(s, dl: DownloadService())
        XCTAssertTrue(b.downloadRows(b.allEpisodeInfos()).isEmpty)
        XCTAssertEqual(b.episodeRows(b.allEpisodeInfos()).count, 1, "Android lists them too; network is checked on play")
    }

    func testCurrentlyPlayingOnlyWhenSomethingIsLoaded() {
        let s = PodcastStore()
        XCTAssertEqual(builder(s).queueSections().count, 1)
        XCTAssertEqual(builder(s, current: PodcastEpisode(id: "c", title: "C")).queueSections().first?.0, "Currently playing")
    }
}
