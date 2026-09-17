package de.danoeh.antennapod.shared.model.playback

enum class MediaType {
    AUDIO,
    VIDEO,
    UNKNOWN;

    companion object {
        private val audioApplicationMimes = setOf(
            "application/ogg",
            "application/opus",
            "application/x-flac",
        )

        fun fromMimeType(mimeType: String?): MediaType {
            if (mimeType.isNullOrBlank()) {
                return UNKNOWN
            }
            return when {
                mimeType.startsWith("audio") -> AUDIO
                mimeType.startsWith("video") -> VIDEO
                mimeType in audioApplicationMimes -> AUDIO
                else -> UNKNOWN
            }
        }
    }
}
