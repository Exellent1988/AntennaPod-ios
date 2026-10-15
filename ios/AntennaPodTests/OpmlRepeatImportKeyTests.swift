import PodcastCore
import XCTest
@testable import AntennaPod

/// OPML import (PodcastStore.importOpml) uses the same podcast equality as gpodder sync:
/// `FeedURLKey` against feedUrl + aliases. So an OPML file after a gpodder import (or the
/// other way round) never adds a podcast twice and never refetches a known alias.
@MainActor
final class OpmlRepeatImportKeyTests: XCTestCase {
    private func key(_ s: String) -> String { PodcastStore.opmlSubscriptionKey(s) }

    func testOpmlKeyIsTheGpodderKey() {
        for u in ["https://a.example/feed", "http://A.example/feed/", "  https://a.example/Feed  ",
                  "feed://a.example/feed", "https://b.example/rss?x=1"] {
            XCTAssertEqual(key(u), FeedURLKey.key(u), u)
        }
        XCTAssertEqual(key("http://a.example/feed"), key("https://A.example/feed/"))
        XCTAssertNotEqual(key("https://b.example/rss?x=1"), key("https://b.example/rss?x=2"))
    }

    func testUnparseableOutlinesStaySeparate() {
        XCTAssertNotEqual(key("not a url"), key("also not"))
    }

    /// Every outline is a known podcast (alias, scheme/slash/case variant): all skipped, no fetch,
    /// library unchanged.
    func testOpmlSkipsAliasesAndVariantsOfSubscribedPodcasts() async {
        let store = PodcastStore()
        let saved = store.feeds
        defer { store.feeds = saved }
        var lnp = PodcastFeed(
            id: UUID(), title: "LNP", feedUrl: "https://logbuch-netzpolitik.de/feed/mp3", siteLink: nil, imageUrl: nil,
            descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
            isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: [])
        lnp.addAlternateUrl("https://feeds.metaebene.me/lnp/mp3")
        store.feeds = [lnp]
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>t</title></head><body>
        <outline type="rss" text="alias" xmlUrl="http://feeds.metaebene.me/lnp/mp3/"/>
        <outline type="rss" text="variant" xmlUrl="http://LOGBUCH-netzpolitik.de/feed/mp3/"/>
        <outline type="rss" text="itpc" xmlUrl="itpc://feeds.metaebene.me/lnp/mp3"/>
        </body></opml>
        """
        await store.importOpml(data: Data(opml.utf8))
        let state = store.opmlImport
        XCTAssertEqual(state.failures.count, 0, "\(state.failures.map(\.url))")
        XCTAssertEqual(state.succeeded, 0)
        XCTAssertEqual(state.skipped, 1, "three outlines are one podcast: deduped to one, then skipped")
        XCTAssertEqual(store.feeds.count, 1)
        XCTAssertEqual(store.feeds.first?.feedUrl, "https://logbuch-netzpolitik.de/feed/mp3", "stored URL unchanged")
    }
}
