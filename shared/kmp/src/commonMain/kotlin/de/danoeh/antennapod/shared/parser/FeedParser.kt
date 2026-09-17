package de.danoeh.antennapod.shared.parser

import com.fleeksoft.ksoup.Ksoup
import com.fleeksoft.ksoup.nodes.Element
import com.fleeksoft.ksoup.parser.Parser
import de.danoeh.antennapod.shared.model.feed.Feed
import de.danoeh.antennapod.shared.model.feed.FeedFunding
import de.danoeh.antennapod.shared.model.feed.FeedItem
import de.danoeh.antennapod.shared.model.feed.FeedMedia

object FeedParser {
    fun parse(xml: String): Feed {
        val document = Ksoup.parse(xml, Parser.xmlParser())
        val root = document.children().firstOrNull { it.tagName().equals("rss", true) || it.tagName().equals("feed", true) }
            ?: document.selectFirst("rss")
            ?: document.selectFirst("feed")
            ?: error("Unsupported feed: missing rss/feed root")
        return when {
            root.tagName().equals("rss", true) -> parseRss(root)
            else -> parseAtom(root)
        }
    }

    private fun parseRss(rss: Element): Feed {
        val channel = rss.selectFirst("channel") ?: error("RSS feed missing channel")
        val feed = Feed(
            type = Feed.TYPE_RSS2,
            title = textOrNull(channel, "title"),
            descriptionText = textOrNull(channel, "description"),
            link = firstNonBlank(
                channelChildren(channel, "link").firstOrNull { it.attr("href").isBlank() }?.ownText()?.trim(),
                textOrNull(channel, "link"),
            ),
            language = textOrNull(channel, "language"),
            imageUrl = channel.selectFirst("image > url")?.text()?.trim()?.takeIf { it.isNotEmpty() },
        )
        feed.paymentLinks.addAll(parsePaymentLinks(channel))
        for (itemElement in channelChildren(channel, "item")) {
            feed.items.add(parseRssItem(itemElement, feed.imageUrl))
        }
        return feed
    }

    private fun parseRssItem(itemElement: Element, feedImageUrl: String?): FeedItem {
        val item = FeedItem(
            title = textOrNull(itemElement, "title"),
            descriptionText = textOrNull(itemElement, "description"),
            link = textOrNull(itemElement, "link"),
            itemIdentifier = textOrNull(itemElement, "guid") ?: textOrNull(itemElement, "link"),
            pubDateEpochMs = FeedDateParser.parseToEpochMs(textOrNull(itemElement, "pubDate")),
            imageUrl = itemElement.selectFirst("image > url")?.text()?.trim()?.takeIf { it.isNotEmpty() },
        )
        item.media = parseEnclosure(itemElement) ?: parseMediaContent(itemElement)
        parseTranscript(itemElement)?.let { (url, type) ->
            item.transcriptUrl = url
            item.transcriptType = type
        }
        if (item.imageUrl == null) {
            item.imageUrl = feedImageUrl
        }
        return item
    }

    private fun parseAtom(feedElement: Element): Feed {
        val feed = Feed(
            type = Feed.TYPE_ATOM1,
            title = textOrNull(feedElement, "title"),
            descriptionText = textOrNull(feedElement, "subtitle") ?: textOrNull(feedElement, "summary"),
            feedIdentifier = textOrNull(feedElement, "id"),
            link = atomLinkHref(feedElement, "alternate") ?: atomLinkHref(feedElement, null),
            imageUrl = textOrNull(feedElement, "logo") ?: textOrNull(feedElement, "icon"),
        )
        for (link in namedChildren(feedElement, "link")) {
            if (link.attr("rel").equals("payment", true)) {
                val href = link.attr("href").trim()
                if (href.isNotEmpty()) {
                    feed.paymentLinks.add(FeedFunding(href, link.text().trim().ifEmpty { null }))
                }
            }
        }
        for (entry in namedChildren(feedElement, "entry")) {
            feed.items.add(parseAtomEntry(entry, feed.imageUrl))
        }
        return feed
    }

    private fun parseAtomEntry(entry: Element, feedImageUrl: String?): FeedItem {
        val item = FeedItem(
            title = textOrNull(entry, "title"),
            descriptionText = textOrNull(entry, "summary") ?: textOrNull(entry, "content"),
            itemIdentifier = textOrNull(entry, "id"),
            link = atomLinkHref(entry, "alternate") ?: atomLinkHref(entry, null),
            pubDateEpochMs = FeedDateParser.parseToEpochMs(
                textOrNull(entry, "published") ?: textOrNull(entry, "updated")
            ),
            imageUrl = feedImageUrl,
        )
        val enclosure = namedChildren(entry, "link").firstOrNull {
            it.attr("rel").equals("enclosure", true)
        }
        if (enclosure != null) {
            item.media = FeedMedia(
                downloadUrl = enclosure.attr("href").trim().ifEmpty { null },
                size = enclosure.attr("length").toLongOrNull() ?: 0L,
                mimeType = enclosure.attr("type").trim().ifEmpty { null },
            )
        }
        return item
    }

    private fun parseEnclosure(itemElement: Element): FeedMedia? {
        val enclosure = namedChildren(itemElement, "enclosure").firstOrNull() ?: return null
        return FeedMedia(
            downloadUrl = enclosure.attr("url").trim().ifEmpty { null },
            size = enclosure.attr("length").toLongOrNull() ?: 0L,
            mimeType = enclosure.attr("type").trim().ifEmpty { null },
        )
    }

    private fun parseMediaContent(itemElement: Element): FeedMedia? {
        val content = itemElement.selectFirst("media|content")
            ?: namedChildren(itemElement, "content").firstOrNull {
                it.tagName().contains("content", true) && it.hasAttr("url")
            }
            ?: itemElement.children().firstOrNull {
                localName(it).equals("content", true) && it.hasAttr("url")
            }
            ?: return null
        val url = content.attr("url").trim().ifEmpty { return null }
        val mimeType = content.attr("type").trim().ifEmpty {
            when (content.attr("medium").trim().lowercase()) {
                "video" -> "video/*"
                "audio" -> "audio/*"
                else -> null
            }
        }
        return FeedMedia(
            downloadUrl = url,
            size = content.attr("fileSize").toLongOrNull()
                ?: content.attr("length").toLongOrNull()
                ?: 0L,
            mimeType = mimeType,
        )
    }

    private fun parseTranscript(itemElement: Element): Pair<String, String?>? {
        val transcript = itemElement.children().firstOrNull {
            localName(it).equals("transcript", true)
        } ?: return null
        val url = transcript.attr("url").trim().ifEmpty { return null }
        val type = transcript.attr("type").trim().ifEmpty { null }
        return url to type
    }

    private fun parsePaymentLinks(channel: Element): List<FeedFunding> {
        val links = mutableListOf<FeedFunding>()
        for (link in channel.children()) {
            if (!localName(link).equals("link", true)) {
                continue
            }
            if (!link.attr("rel").equals("payment", true)) {
                continue
            }
            val href = link.attr("href").trim()
            if (href.isNotEmpty()) {
                links.add(FeedFunding(href, link.text().trim().ifEmpty { null }))
            }
        }
        for (funding in channel.children()) {
            if (!localName(funding).equals("funding", true)) {
                continue
            }
            val href = funding.attr("url").trim().ifEmpty { funding.text().trim() }
            if (href.isNotEmpty()) {
                links.add(FeedFunding(href, funding.text().trim().ifEmpty { null }))
            }
        }
        return links
    }

    private fun atomLinkHref(parent: Element, rel: String?): String? {
        val links = namedChildren(parent, "link")
        val match = if (rel == null) {
            links.firstOrNull { it.attr("rel").isBlank() || it.attr("rel").equals("alternate", true) }
        } else {
            links.firstOrNull { it.attr("rel").equals(rel, true) }
        }
        return match?.attr("href")?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun textOrNull(parent: Element, tag: String): String? {
        val element = namedChildren(parent, tag).firstOrNull() ?: return null
        return element.text().trim().takeIf { it.isNotEmpty() }
    }

    private fun channelChildren(channel: Element, tag: String): List<Element> = namedChildren(channel, tag)

    private fun namedChildren(parent: Element, tag: String): List<Element> {
        return parent.children().filter { localName(it).equals(tag, true) }
    }

    private fun localName(element: Element): String {
        val name = element.tagName()
        val index = name.indexOf(':')
        return if (index >= 0) name.substring(index + 1) else name
    }

    private fun firstNonBlank(vararg values: String?): String? {
        return values.firstOrNull { !it.isNullOrBlank() }
    }
}
