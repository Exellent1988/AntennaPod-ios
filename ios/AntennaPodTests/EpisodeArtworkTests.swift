import XCTest
@testable import AntennaPod

/// Android Auto parity: episode rows use item artwork (itunes:image in <item>) before feed artwork.
final class EpisodeArtworkTests: XCTestCase {
    private let xml = """
    <?xml version="1.0"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
      <title>Show</title>
      <itunes:image href="https://ex.com/feed.jpg"/>
      <item>
        <title>With art</title><guid>e1</guid>
        <enclosure url="https://ex.com/1.mp3" type="audio/mpeg" length="1"/>
        <itunes:image href="https://ex.com/ep1.jpg"/>
      </item>
      <item>
        <title>Without art</title><guid>e2</guid>
        <enclosure url="https://ex.com/2.mp3" type="audio/mpeg" length="1"/>
      </item>
    </channel>
    </rss>
    """

    func testParserStoresItemImageAndKeepsFeedImage() throws {
        let feed = try NativeRssAtomParser.parse(xml: xml)
        XCTAssertEqual(feed.imageUrl, "https://ex.com/feed.jpg")
        let byTitle = Dictionary(uniqueKeysWithValues: feed.episodes.map { ($0.title, $0) })
        XCTAssertEqual(byTitle["With art"]?.imageUrl, "https://ex.com/ep1.jpg")
        XCTAssertNil(byTitle["Without art"]?.imageUrl)
    }

    func testOldSavedEpisodeJSONDecodesWithoutImageUrl() throws {
        let ep = PodcastEpisode(id: "x", title: "T", imageUrl: "https://ex.com/a.jpg")
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ep)) as! [String: Any]
        XCTAssertEqual(obj["imageUrl"] as? String, "https://ex.com/a.jpg")
        obj.removeValue(forKey: "imageUrl")
        let old = try JSONDecoder().decode(PodcastEpisode.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.imageUrl)
    }

    func testEpisodeArtworkOrder() {
        func url(_ p: String?, _ i: String?, _ fd: String?, _ f: String?) -> String? {
            CarPlayBrowseModel.episodeArtworkURL(podcastImages: p, itemImage: i, feedDisplay: fd, feedImage: f)
        }
        XCTAssertEqual(url("https://p", "https://i", "https://fd", "https://f"), "https://p")
        XCTAssertEqual(url(nil, "https://i", "https://fd", "https://f"), "https://i")
        XCTAssertEqual(url(nil, " ", "https://fd", "https://f"), "https://fd")
        XCTAssertEqual(url(nil, nil, nil, "https://f"), "https://f")
        XCTAssertNil(url(nil, nil, nil, nil))
    }
}
