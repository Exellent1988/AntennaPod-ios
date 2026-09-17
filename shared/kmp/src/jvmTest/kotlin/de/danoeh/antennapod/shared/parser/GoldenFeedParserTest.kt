package de.danoeh.antennapod.shared.parser

import de.danoeh.antennapod.shared.model.feed.Feed
import de.danoeh.antennapod.shared.model.playback.MediaType
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GoldenFeedParserTest {
    @Test
    fun rss2Basic() {
        val feed = parseGolden("feed-rss-testRss2Basic.xml")
        assertEquals(Feed.TYPE_RSS2, feed.type)
        assertEquals("title", feed.title)
        assertEquals("en", feed.language)
        assertEquals("http://example.com", feed.link)
        assertEquals("This is the description", feed.descriptionText)
        assertEquals("http://example.com/payment", feed.paymentLinks[0].url)
        assertEquals("http://example.com/picture", feed.imageUrl)
        assertEquals(10, feed.items.size)
        for (i in feed.items.indices) {
            val item = feed.items[i]
            assertEquals("http://example.com/item-$i", item.itemIdentifier)
            assertEquals("item-$i", item.title)
            assertNull(item.descriptionText)
            assertEquals("http://example.com/items/$i", item.link)
            assertEquals(i * 60_000L, item.pubDateEpochMs)
            assertNull(item.paymentLink)
            assertEquals("http://example.com/picture", item.imageLocation(feed.imageUrl))
            assertTrue(item.hasMedia())
            val media = item.media!!
            assertEquals("http://example.com/media-$i", media.downloadUrl)
            assertEquals(1024L * 1024L, media.size)
            assertEquals("audio/mp3", media.mimeType)
            assertNull(item.chapters)
        }
    }

    @Test
    fun imageWithWhitespace() {
        val feed = parseGolden("feed-rss-testImageWithWhitespace.xml")
        assertEquals("title", feed.title)
        assertEquals("http://example.com", feed.link)
        assertEquals("This is the description", feed.descriptionText)
        assertEquals("http://example.com/payment", feed.paymentLinks[0].url)
        assertEquals("https://example.com/image.png", feed.imageUrl)
        assertEquals(0, feed.items.size)
    }

    @Test
    fun mediaContentMime() {
        val feed = parseGolden("feed-rss-testMediaContentMime.xml")
        assertEquals("title", feed.title)
        assertEquals("http://example.com", feed.link)
        assertEquals("This is the description", feed.descriptionText)
        assertEquals("http://example.com/payment", feed.paymentLinks[0].url)
        assertNull(feed.imageUrl)
        assertEquals(1, feed.items.size)
        val media = feed.items[0].media!!
        assertEquals(MediaType.VIDEO, media.getMediaType())
        assertEquals("https://www.example.com/file.mp4", media.downloadUrl)
    }

    @Test
    fun podcastIndexTranscript() {
        val feed = parseGolden("feed-rss-testPodcastIndexTranscript.xml")
        assertEquals("https://podnews.net/audio/podnews231011.mp3.json", feed.items[0].transcriptUrl)
        assertEquals("application/json", feed.items[0].transcriptType)
    }

    @Test
    fun atomBasic() {
        val feed = parseGolden("feed-atom-testAtomBasic.xml")
        assertEquals(Feed.TYPE_ATOM1, feed.type)
        assertEquals("title", feed.title)
        assertEquals("http://example.com/feed", feed.feedIdentifier)
        assertEquals("http://example.com", feed.link)
        assertEquals("This is the description", feed.descriptionText)
        assertEquals("http://example.com/payment", feed.paymentLinks[0].url)
        assertEquals("http://example.com/picture", feed.imageUrl)
        assertEquals(10, feed.items.size)
        for (i in feed.items.indices) {
            val item = feed.items[i]
            assertEquals("http://example.com/item-$i", item.itemIdentifier)
            assertEquals("item-$i", item.title)
            assertNull(item.descriptionText)
            assertEquals("http://example.com/items/$i", item.link)
            assertEquals(i * 60_000L, item.pubDateEpochMs)
            assertNull(item.paymentLink)
            assertEquals("http://example.com/picture", item.imageLocation(feed.imageUrl))
            assertTrue(item.hasMedia())
            val media = item.media!!
            assertEquals("http://example.com/media-$i", media.downloadUrl)
            assertEquals(1024L * 1024L, media.size)
            assertEquals("audio/mp3", media.mimeType)
            assertNull(item.chapters)
        }
    }

    private fun parseGolden(name: String): Feed {
        val file = File("../specs/feeds/golden", name)
        assertTrue(file.exists(), "Missing golden fixture: ${file.canonicalPath}")
        return FeedParser.parse(file.readText())
    }
}
