package de.danoeh.antennapod.shared.model.feed

data class Chapter(
    var id: Long = 0,
    var start: Long = 0,
    var title: String? = null,
    var link: String? = null,
    var imageUrl: String? = null,
    var chapterId: String? = null,
)
