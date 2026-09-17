package de.danoeh.antennapod.shared.model.feed

import de.danoeh.antennapod.shared.model.playback.MediaType

data class FeedMedia(
    var downloadUrl: String? = null,
    var size: Long = 0,
    var mimeType: String? = null,
    var duration: Int = 0,
    var position: Int = 0,
) {
    fun getMediaType(): MediaType = MediaType.fromMimeType(mimeType)
}
