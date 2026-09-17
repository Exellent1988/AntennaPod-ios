import Foundation

struct PodcastEpisode: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var link: String?
    var pubDateEpochMs: Int64?
    var downloadUrl: String?
    var mimeType: String?
    var size: Int64
    var transcriptUrl: String?
}

struct PodcastFeed: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var feedUrl: String
    var siteLink: String?
    var imageUrl: String?
    var descriptionText: String?
    var episodes: [PodcastEpisode]
}
