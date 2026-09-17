package de.danoeh.antennapod.shared.model.feed

data class Feed(
    var type: String? = null,
    var title: String? = null,
    var customTitle: String? = null,
    var feedIdentifier: String? = null,
    var link: String? = null,
    var descriptionText: String? = null,
    var language: String? = null,
    var author: String? = null,
    var imageUrl: String? = null,
    var downloadUrl: String? = null,
    var items: MutableList<FeedItem> = mutableListOf(),
    var paymentLinks: MutableList<FeedFunding> = mutableListOf(),
) {
    companion object {
        const val TYPE_RSS2: String = "rss"
        const val TYPE_ATOM1: String = "atom"
    }

    fun displayTitle(): String? = if (!customTitle.isNullOrBlank()) customTitle else title
}
