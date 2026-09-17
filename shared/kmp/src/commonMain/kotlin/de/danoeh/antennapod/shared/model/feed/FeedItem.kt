package de.danoeh.antennapod.shared.model.feed

data class FeedItem(
    var itemIdentifier: String? = null,
    var title: String? = null,
    var description: String? = null,
    var link: String? = null,
    var pubDateEpochMs: Long? = null,
    var media: FeedMedia? = null,
    var paymentLink: String? = null,
    var imageUrl: String? = null,
    var chapters: List<Chapter>? = null,
    var transcriptUrl: String? = null,
    var transcriptType: String? = null,
) {
    fun hasMedia(): Boolean = media != null

    fun imageLocation(feedImageUrl: String?): String? = imageUrl ?: feedImageUrl
}
