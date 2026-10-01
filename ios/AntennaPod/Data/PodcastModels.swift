import Foundation

/// Chapter marker from feed (Podlove Simple Chapters / Podcast Index), remote JSON, or local media-file tags.
struct PodcastChapter: Identifiable, Hashable, Codable {
    var id: String { "\(startTimeSeconds)|\(title)" }
    var title: String
    /// Start offset from episode beginning.
    var startTimeSeconds: Double
    var href: String?
    var imageUrl: String?

    init(title: String, startTimeSeconds: Double, href: String? = nil, imageUrl: String? = nil) {
        self.title = title
        self.startTimeSeconds = startTimeSeconds
        self.href = href
        self.imageUrl = imageUrl
    }
}



/// Podcast Index `podcast:trailer` — channel-level teaser media when the feed provides it.
/// Element text = title (required to keep); attributes `url`, `pubdate`, optional `length` / `type` / `season`.
/// **Feed-provided only** — never invent trailers. Distinct from item `itunes:episodeType=trailer` (EpisodeRow badge).
struct PodcastTrailer: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String { "\(title)|\(url ?? "")|\(pubDate ?? "")|\(season.map(String.init) ?? "")" }
    /// Trailer title from element text (required by Podcast Index; may be truncated ~128 chars by aggregators).
    var title: String
    /// Raw `pubdate` attribute (RFC2822) when provided.
    var pubDate: String?
    /// Parsed `pubdate` epoch ms when parsable; nil when missing/unparsable — never invent.
    var pubDateEpochMs: Int64?
    /// Media URL string from `url` attribute when provided.
    var url: String?
    /// Optional file size in bytes from `length`.
    var length: Int64?
    /// Optional MIME type from `type` (e.g. audio/mp3, video/mp4).
    var type: String?
    /// Optional season number this trailer previews.
    var season: Int?

    init(
        title: String,
        pubDate: String? = nil,
        pubDateEpochMs: Int64? = nil,
        url: String? = nil,
        length: Int64? = nil,
        type: String? = nil,
        season: Int? = nil
    ) {
        self.title = title
        self.pubDate = pubDate
        self.pubDateEpochMs = pubDateEpochMs
        self.url = url
        self.length = length
        self.type = type
        self.season = season
    }

    /// Trimmed non-empty title. Nil when blank.
    var displayTitle: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) media URL from feed `url` only. Nil when missing / non-http(s).
    var mediaURL: URL? {
        guard let url else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = URL(string: trimmed) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// True when MIME or URL extension looks like audio/video enclosure media (prefer in-app play).
    var looksLikePlayableMedia: Bool {
        if let mime = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !mime.isEmpty {
            if mime.hasPrefix("audio/") || mime.hasPrefix("video/") {
                return true
            }
        }
        return Self.mediaFileExtension(from: url) != nil
    }

    /// Prefer `PlaybackService` when http(s) URL looks enclosure-like; otherwise openURL for other http(s).
    var prefersInAppPlayback: Bool {
        mediaURL != nil && looksLikePlayableMedia
    }

    private static let mediaExtensions: Set<String> = [
        "mp3", "m4a", "aac", "ogg", "opus", "wav", "flac",
        "mp4", "m4v", "mov", "webm"
    ]

    private static func mediaFileExtension(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        let path: String
        if let parsed = URL(string: urlString) {
            path = parsed.path
        } else {
            path = urlString.split(separator: "?", maxSplits: 1).first.map(String.init) ?? urlString
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return mediaExtensions.contains(ext) ? ext : nil
    }

    /// Synthetic episode for `PlaybackService.play` — not added to `PodcastFeed.episodes`.
    /// Id embeds feed UUID so Now Playing can resolve artwork/title via `feed(containingEpisodeId:)`.
    func asPlaybackEpisode(feedId: UUID) -> PodcastEpisode? {
        guard let media = mediaURL else { return nil }
        let titleText = displayTitle ?? title
        return PodcastEpisode(
            id: "podcast-trailer:\(feedId.uuidString):\(media.absoluteString)",
            title: titleText,
            link: nil,
            pubDateEpochMs: pubDateEpochMs,
            downloadUrl: media.absoluteString,
            mimeType: type,
            size: length ?? 0,
            transcriptUrl: nil,
            transcriptType: nil,
            chapters: [],
            podcastIndexChapterUrl: nil,
            descriptionText: nil,
            durationSeconds: 0,
            seasonNumber: season,
            episodeNumber: nil,
            episodeType: "trailer",
            isExplicit: false,
            people: []
        )
    }
}

/// Display helpers for channel `podcast:trailer` (feed-provided only).
enum PodcastTrailerDisplay {
    /// Non-empty titled trailers in feed order (no invented entries).
    static func valid(_ trailers: [PodcastTrailer]) -> [PodcastTrailer] {
        trailers.compactMap { trailer in
            guard let title = trailer.displayTitle else { return nil }
            return PodcastTrailer(
                title: title,
                pubDate: trailer.pubDate,
                pubDateEpochMs: trailer.pubDateEpochMs,
                url: trailer.url,
                length: trailer.length,
                type: trailer.type,
                season: trailer.season
            )
        }
    }

    /// Most recent trailer by `pubDateEpochMs` (Podcast Index: choose latest when several).
    /// Missing/unparsable dates sort as oldest. Nil when none.
    static func mostRecent(_ trailers: [PodcastTrailer]) -> PodcastTrailer? {
        let list = valid(trailers)
        guard !list.isEmpty else { return nil }
        return list.max { lhs, rhs in
            (lhs.pubDateEpochMs ?? Int64.min) < (rhs.pubDateEpochMs ?? Int64.min)
        }
    }
}

/// Podcast Index `podcast:person` — feed-provided credits only (never invent people).
/// Name is element text; optional `role` / `group` / `href` / `img` attributes when set.
/// Spec defaults (host/cast) are **not** assumed here — UI shows role only when the feed set it.
struct PodcastPerson: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields (names can repeat).
    var id: String { "\(name)|\(role ?? "")|\(group ?? "")|\(href ?? "")|\(img ?? "")" }
    var name: String
    /// Optional `role` attribute as provided (e.g. host, guest). Nil when absent — never invent "host".
    var role: String?
    /// Optional `group` attribute as provided (e.g. cast, writing). Nil when absent — never invent "cast".
    var group: String?
    /// Optional profile / homepage URL string from `href`.
    var href: String?
    /// Optional avatar URL string from `img` (v1 UI may omit remote fetch).
    var img: String?

    init(name: String, role: String? = nil, group: String? = nil, href: String? = nil, img: String? = nil) {
        self.name = name
        self.role = role
        self.group = group
        self.href = href
        self.img = img
    }

    /// Trimmed non-empty name. Nil when blank.
    var displayName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty role when the feed set `role`. Hidden when missing — never invent.
    var displayRole: String? {
        guard let role else { return nil }
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) profile URL from feed `href` only. Nil when missing / non-http(s).
    var profileURL: URL? {
        guard let href else { return nil }
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

/// Display helpers for `podcast:person` lists (channel or item). Feed-provided only.
enum PodcastPeopleDisplay {
    /// Soft UI cap — show first N, honesty footnote when more exist in the feed.
    static let displayCap = 20

    /// Non-empty named people in feed order (no invented entries).
    static func valid(_ people: [PodcastPerson]) -> [PodcastPerson] {
        people.compactMap { person in
            guard let name = person.displayName else { return nil }
            return PodcastPerson(
                name: name,
                role: person.displayRole,
                group: person.group.flatMap { g in
                    let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                },
                href: person.href,
                img: person.img
            )
        }
    }

    /// First `displayCap` people + whether the feed listed more.
    static func capped(_ people: [PodcastPerson]) -> (shown: [PodcastPerson], truncated: Bool) {
        let list = valid(people)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }
}

struct PodcastEpisode: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var link: String?
    var pubDateEpochMs: Int64?
    var downloadUrl: String?
    var mimeType: String?
    var size: Int64
    var transcriptUrl: String?
    /// Podcast Index transcript MIME (`application/json`, `text/vtt`, `application/srt`, …).
    var transcriptType: String?
    /// Chapters: feed PSC/Atom, fetched Podcast Index JSON, or media-file tags (when persisted after local read).
    var chapters: [PodcastChapter]
    /// Podcast Index `podcast:chapters` remote JSON URL (fetched lazily when needed).
    var podcastIndexChapterUrl: String?
    /// Episode shownotes / description from RSS (`description` / `content:encoded` / Atom `summary` / `content`).
    /// May contain HTML; UI strips tags to plain text for beta display.
    var descriptionText: String?
    /// Feed-declared duration in seconds (`itunes:duration` / Media RSS `media:content@duration`).
    /// `0` = unknown / missing. Prefer this for list rows; playback may refine via `EpisodePlaybackState.durationSeconds`.
    var durationSeconds: Double
    /// iTunes season number from `itunes:season`. `nil` = not in feed — never invent sequential seasons.
    var seasonNumber: Int?
    /// iTunes episode number from `itunes:episode`. `nil` = not in feed — never invent sequential episode numbers.
    var episodeNumber: Int?
    /// iTunes episode type from `itunes:episodeType` (`full` / `trailer` / `bonus`). `nil` = not in feed.
    var episodeType: String?
    /// `itunes:explicit` yes/true/explicit on the item (or inherited from channel when item omits it).
    /// `false` when missing, clean/no/false, or unknown — never invent; UI hides badge unless true.
    var isExplicit: Bool
    /// Item-level Podcast Index `podcast:person` entries when the feed provides them.
    /// Empty when absent — never invent people; UI hides when empty.
    var people: [PodcastPerson]

    /// Feed provides a remote transcript URL (no on-device STT).
    var hasTranscriptURL: Bool {
        guard let transcriptUrl, !transcriptUrl.isEmpty else { return false }
        return true
    }

    /// Video episode when enclosure MIME is `video/*` or the media URL ends in a common video extension.
    /// Used by the full player video surface (beta lite). Not every `video/mp4` feed is guaranteed playable.
    var isVideo: Bool {
        if let mime = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           mime.hasPrefix("video/") {
            return true
        }
        return Self.videoFileExtension(from: downloadUrl) != nil
    }

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm"]

    /// Lowercased path extension when it looks like a video file; ignores query/fragment.
    private static func videoFileExtension(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        let path: String
        if let url = URL(string: urlString) {
            path = url.path
        } else {
            path = urlString.split(separator: "?", maxSplits: 1).first.map(String.init) ?? urlString
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext) ? ext : nil
    }

    init(
        id: String,
        title: String,
        link: String? = nil,
        pubDateEpochMs: Int64? = nil,
        downloadUrl: String? = nil,
        mimeType: String? = nil,
        size: Int64 = 0,
        transcriptUrl: String? = nil,
        transcriptType: String? = nil,
        chapters: [PodcastChapter] = [],
        podcastIndexChapterUrl: String? = nil,
        descriptionText: String? = nil,
        durationSeconds: Double = 0,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeType: String? = nil,
        isExplicit: Bool = false,
        people: [PodcastPerson] = []
    ) {
        self.id = id
        self.title = title
        self.link = link
        self.pubDateEpochMs = pubDateEpochMs
        self.downloadUrl = downloadUrl
        self.mimeType = mimeType
        self.size = size
        self.transcriptUrl = transcriptUrl
        self.transcriptType = transcriptType
        self.chapters = chapters
        self.podcastIndexChapterUrl = podcastIndexChapterUrl
        self.descriptionText = descriptionText
        self.durationSeconds = durationSeconds
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeType = episodeType
        self.isExplicit = isExplicit
        self.people = people
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        pubDateEpochMs = try c.decodeIfPresent(Int64.self, forKey: .pubDateEpochMs)
        downloadUrl = try c.decodeIfPresent(String.self, forKey: .downloadUrl)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        transcriptUrl = try c.decodeIfPresent(String.self, forKey: .transcriptUrl)
        transcriptType = try c.decodeIfPresent(String.self, forKey: .transcriptType)
        chapters = try c.decodeIfPresent([PodcastChapter].self, forKey: .chapters) ?? []
        podcastIndexChapterUrl = try c.decodeIfPresent(String.self, forKey: .podcastIndexChapterUrl)
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber)
        episodeType = try c.decodeIfPresent(String.self, forKey: .episodeType)
        isExplicit = try c.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
        people = try c.decodeIfPresent([PodcastPerson].self, forKey: .people) ?? []
    }

    /// Non-empty named item-level `podcast:person` entries (hide when empty — never invent).
    var displayPeople: [PodcastPerson] {
        PodcastPeopleDisplay.valid(people)
    }

    /// Non-empty shownotes / description from the feed (may still contain HTML).
    var hasDescriptionText: Bool {
        guard let descriptionText else { return false }
        return !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Finite feed duration greater than zero (hide when unknown).
    var hasKnownDuration: Bool {
        durationSeconds.isFinite && durationSeconds > 0
    }

    /// Compact season/episode from iTunes tags only (`S2 E5`, `S2`, or `E5`).
    /// `nil` when neither season nor episode is in the feed — never invents numbers.
    var seasonEpisodeCaption: String? {
        switch (seasonNumber, episodeNumber) {
        case let (season?, episode?):
            return "S\(season) E\(episode)"
        case let (season?, nil):
            return "S\(season)"
        case let (nil, episode?):
            return "E\(episode)"
        default:
            return nil
        }
    }

    /// VoiceOver phrasing for season/episode numbers when present.
    var seasonEpisodeAccessibilityLabel: String? {
        switch (seasonNumber, episodeNumber) {
        case let (season?, episode?):
            return String(localized: "Season \(season), Episode \(episode)")
        case let (season?, nil):
            return String(localized: "Season \(season)")
        case let (nil, episode?):
            return String(localized: "Episode \(episode)")
        default:
            return nil
        }
    }

    /// Localized Trailer / Bonus when `itunes:episodeType` is trailer or bonus.
    /// `full` and unknown/missing stay hidden (full is the default).
    var episodeTypeCaption: String? {
        guard let raw = episodeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "trailer":
            return String(localized: "Trailer")
        case "bonus":
            return String(localized: "Bonus")
        default:
            return nil
        }
    }
}

struct PodcastFeed: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var feedUrl: String
    var siteLink: String?
    var imageUrl: String?
    /// Channel / feed description from RSS (`description` / Atom `subtitle` / `summary`). May contain HTML.
    var descriptionText: String?
    /// Podcast author when the feed provides it (`itunes:author` / Atom `author`/`name` / RSS `managingEditor`).
    /// Nil or blank when absent — never invented from discovery hints alone.
    var author: String?
    /// Channel `itunes:explicit` yes/true/explicit. `false` when missing/clean — never invent; UI hides unless true.
    var isExplicit: Bool
    /// Feed language BCP-47 / ISO 639 code when the feed provides it (`itunes:language` / RSS `language` / `xml:lang`).
    /// Nil or blank when absent — never invent; UI hides unless present.
    var language: String?
    /// Podcast Index `podcast:funding` / Atom `link rel="payment"` URL when the feed provides it.
    /// Nil or blank when absent — never invent; UI hides unless http(s) valid.
    var fundingUrl: String?
    /// Optional creator-supplied label for the funding link (`podcast:funding` text). Nil when absent / Atom payment-only.
    var fundingLabel: String?
    /// Channel `itunes:category` `text` attributes (parent + nested subcategory), feed order, de-duped.
    /// Empty when absent — never invent App Store taxonomy; UI hides when empty.
    var categories: [String]
    /// Podcast Index `podcast:locked` channel claim (`yes` → true). `false` when absent/`no` — never invent; UI hides unless true.
    /// Display-only: this app does **not** verify ownership or block host transfer.
    var isLocked: Bool
    /// Optional `owner` email attribute on `podcast:locked` when the feed provides it. Nil when absent — never invent.
    var lockedOwner: String?
    /// Podcast Index channel `podcast:guid` (UUIDv5 string) when the feed provides it.
    /// Nil or blank when absent — **never invent** / never generate from feed URL; display/copy only (not subscription primary key).
    /// Distinct from per-episode RSS `guid` / Atom `id`.
    var podcastGuid: String?
    /// Channel-level Podcast Index `podcast:person` entries when the feed provides them.
    /// Empty when absent — never invent people; UI hides when empty.
    var people: [PodcastPerson]
    /// Channel-level Podcast Index `podcast:trailer` entries when the feed provides them.
    /// Empty when absent — never invent trailers; UI hides when empty.
    /// Distinct from item `itunes:episodeType=trailer` (EpisodeRow Trailer badge).
    var trailers: [PodcastTrailer]
    var episodes: [PodcastEpisode]

    /// Non-empty feed description (may still contain HTML).
    var hasDescriptionText: Bool {
        guard let descriptionText else { return false }
        return !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Trimmed non-empty author for UI / VoiceOver / search. Hidden when missing.
    var displayAuthor: String? {
        guard let author else { return nil }
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty language code from the feed. Hidden when missing — never invent.
    var languageCode: String? {
        guard let language else { return nil }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Localized language name for UI / VoiceOver when `Locale` knows the code; otherwise the raw code.
    /// `nil` when the feed did not provide a language — never invents a code.
    var displayLanguage: String? {
        guard let code = languageCode else { return nil }
        return FeedLanguageFormatting.displayName(for: code)
    }

    /// Trimmed non-empty funding label from the feed when provided. Hidden/fallback when missing.
    var displayFundingLabel: String? {
        guard let fundingLabel else { return nil }
        let trimmed = fundingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Non-empty trimmed category strings from the feed (`itunes:category` text). Empty → hide UI.
    var displayCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in categories {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    /// Caption joining display categories with " · " for compact rows / VoiceOver. Nil when none.
    var categoriesCaption: String? {
        let list = displayCategories
        guard !list.isEmpty else { return nil }
        return list.joined(separator: " · ")
    }

    /// Trimmed non-empty locked-owner email from the feed when provided. Hidden when missing.
    var displayLockedOwner: String? {
        guard let lockedOwner else { return nil }
        let trimmed = lockedOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty Podcast Index `podcast:guid` from the feed. Hidden when missing — never invent.
    var displayPodcastGuid: String? {
        guard let podcastGuid else { return nil }
        let trimmed = podcastGuid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Non-empty named channel-level `podcast:person` entries (hide when empty — never invent).
    var displayPeople: [PodcastPerson] {
        PodcastPeopleDisplay.valid(people)
    }

    /// Non-empty titled channel `podcast:trailer` entries (hide when empty — never invent).
    var displayTrailers: [PodcastTrailer] {
        PodcastTrailerDisplay.valid(trailers)
    }

    /// Most recent channel trailer by pubdate (Podcast Index multi-trailer rule). Nil when none.
    var displayTrailer: PodcastTrailer? {
        PodcastTrailerDisplay.mostRecent(trailers)
    }

    init(
        id: UUID,
        title: String,
        feedUrl: String,
        siteLink: String? = nil,
        imageUrl: String? = nil,
        descriptionText: String? = nil,
        author: String? = nil,
        isExplicit: Bool = false,
        language: String? = nil,
        fundingUrl: String? = nil,
        fundingLabel: String? = nil,
        categories: [String] = [],
        isLocked: Bool = false,
        lockedOwner: String? = nil,
        podcastGuid: String? = nil,
        people: [PodcastPerson] = [],
        trailers: [PodcastTrailer] = [],
        episodes: [PodcastEpisode]
    ) {
        self.id = id
        self.title = title
        self.feedUrl = feedUrl
        self.siteLink = siteLink
        self.imageUrl = imageUrl
        self.descriptionText = descriptionText
        self.author = author
        self.isExplicit = isExplicit
        self.language = language
        self.fundingUrl = fundingUrl
        self.fundingLabel = fundingLabel
        self.categories = categories
        self.isLocked = isLocked
        self.lockedOwner = lockedOwner
        self.podcastGuid = podcastGuid
        self.people = people
        self.trailers = trailers
        self.episodes = episodes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        feedUrl = try c.decode(String.self, forKey: .feedUrl)
        siteLink = try c.decodeIfPresent(String.self, forKey: .siteLink)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        isExplicit = try c.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
        language = try c.decodeIfPresent(String.self, forKey: .language)
        fundingUrl = try c.decodeIfPresent(String.self, forKey: .fundingUrl)
        fundingLabel = try c.decodeIfPresent(String.self, forKey: .fundingLabel)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        lockedOwner = try c.decodeIfPresent(String.self, forKey: .lockedOwner)
        podcastGuid = try c.decodeIfPresent(String.self, forKey: .podcastGuid)
        people = try c.decodeIfPresent([PodcastPerson].self, forKey: .people) ?? []
        trailers = try c.decodeIfPresent([PodcastTrailer].self, forKey: .trailers) ?? []
        episodes = try c.decodeIfPresent([PodcastEpisode].self, forKey: .episodes) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, feedUrl, siteLink, imageUrl, descriptionText, author, isExplicit, language, fundingUrl, fundingLabel, categories, isLocked, lockedOwner, podcastGuid, people, trailers, episodes
    }
}

/// Localized display for feed-provided language codes (RSS / itunes / xml:lang).
/// Uses `Locale.current` only — never invents or remaps codes the feed did not supply.
enum FeedLanguageFormatting {
    /// Prefer `Locale.current.localizedString(forLanguageCode:)` / identifier; fall back to the raw code.
    static func displayName(for rawCode: String) -> String {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return rawCode }
        // Full BCP-47 identifier first (e.g. en-US).
        if let name = Locale.current.localizedString(forIdentifier: code)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           name.caseInsensitiveCompare(code) != .orderedSame {
            return name
        }
        // Language subtag only (en from en-US / en_US).
        let langOnly = code
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? code
        if let name = Locale.current.localizedString(forLanguageCode: langOnly)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return code
    }
}

/// Per-episode playback progress and played flag (keyed by episode id / guid).
struct EpisodePlaybackState: Hashable, Codable {
    var positionSeconds: Double
    var durationSeconds: Double
    var isPlayed: Bool
    var updatedAtEpochMs: Int64
    /// Last time the user played or marked this episode played (History sort key).
    /// Distinct from `updatedAtEpochMs`, which also bumps on mark-unplayed.
    var lastPlayedAtEpochMs: Int64?

    static func empty(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> EpisodePlaybackState {
        EpisodePlaybackState(
            positionSeconds: 0,
            durationSeconds: 0,
            isPlayed: false,
            updatedAtEpochMs: nowMs,
            lastPlayedAtEpochMs: nil
        )
    }

    init(
        positionSeconds: Double,
        durationSeconds: Double,
        isPlayed: Bool,
        updatedAtEpochMs: Int64,
        lastPlayedAtEpochMs: Int64? = nil
    ) {
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isPlayed = isPlayed
        self.updatedAtEpochMs = updatedAtEpochMs
        self.lastPlayedAtEpochMs = lastPlayedAtEpochMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        positionSeconds = try c.decodeIfPresent(Double.self, forKey: .positionSeconds) ?? 0
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        isPlayed = try c.decodeIfPresent(Bool.self, forKey: .isPlayed) ?? false
        updatedAtEpochMs = try c.decodeIfPresent(Int64.self, forKey: .updatedAtEpochMs)
            ?? Int64(Date().timeIntervalSince1970 * 1000)
        lastPlayedAtEpochMs = try c.decodeIfPresent(Int64.self, forKey: .lastPlayedAtEpochMs)
        // Migrate older `playback.json` without `lastPlayedAtEpochMs`.
        if lastPlayedAtEpochMs == nil, isPlayed || positionSeconds > 0 {
            lastPlayedAtEpochMs = updatedAtEpochMs
        }
    }

    /// Whether this state should appear in History (played or in-progress).
    var belongsInHistory: Bool {
        isPlayed || positionSeconds > 1
    }

    private enum CodingKeys: String, CodingKey {
        case positionSeconds, durationSeconds, isPlayed, updatedAtEpochMs, lastPlayedAtEpochMs
    }
}

/// Episode row for the Inbox tab (cross-feed unplayed list).
struct InboxEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
}

/// Episode hit from local library search (title / feed title / descriptions).
struct LibraryEpisodeHit: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let feedId: UUID
}

/// Episode row for History (played / in-progress), newest last-played first.
struct HistoryEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let lastPlayedAtEpochMs: Int64
}

/// Episode row for Favorites (starred), newest favorited first.
struct FavoriteEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let favoritedAtEpochMs: Int64
}

/// Episode row for Archived, newest archived first.
struct ArchivedEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let archivedAtEpochMs: Int64
}

enum ChapterIndexing {
    /// AntennaPod-like: if farther than this into the current chapter, Previous restarts it.
    static let previousRestartThresholdSeconds: Double = 2

    /// Index of the chapter active at `positionSeconds`, or `nil` if before the first chapter / empty.
    static func currentIndex(in chapters: [PodcastChapter], at positionSeconds: Double) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var current: Int?
        for (i, chapter) in chapters.enumerated() {
            if chapter.startTimeSeconds <= positionSeconds {
                current = i
            } else {
                break
            }
        }
        return current
    }

    /// Seek target for Previous chapter, or `nil` when there are no chapters.
    /// If >`previousRestartThresholdSeconds` into the current chapter → chapter start;
    /// otherwise → previous chapter start (or `0` on the first chapter).
    static func previousSeekSeconds(in chapters: [PodcastChapter], at positionSeconds: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        guard let index = currentIndex(in: chapters, at: positionSeconds) else {
            return 0
        }
        let start = chapters[index].startTimeSeconds
        if positionSeconds - start > previousRestartThresholdSeconds {
            return start
        }
        if index == 0 {
            return 0
        }
        return chapters[index - 1].startTimeSeconds
    }

    /// Seek target for Next chapter (start of the chapter after the current one), or `nil`
    /// when there are no chapters / already on the last chapter.
    static func nextSeekSeconds(in chapters: [PodcastChapter], at positionSeconds: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        if let index = currentIndex(in: chapters, at: positionSeconds) {
            let next = index + 1
            guard next < chapters.count else { return nil }
            return chapters[next].startTimeSeconds
        }
        // Before the first chapter → jump to it.
        return chapters[0].startTimeSeconds
    }

    /// End of chapter at `index`: next chapter start, or `episodeDurationSeconds` for the last
    /// chapter when a known finite duration is provided. `nil` when index is invalid, or when
    /// this is the last chapter and episode duration is unknown (cannot invent an end).
    /// Wall-clock offsets only — no playback-speed divide.
    static func endSeconds(
        in chapters: [PodcastChapter],
        atIndex index: Int,
        episodeDurationSeconds: Double?
    ) -> Double? {
        guard index >= 0, index < chapters.count else { return nil }
        let next = index + 1
        if next < chapters.count {
            let end = chapters[next].startTimeSeconds
            guard end.isFinite, end >= chapters[index].startTimeSeconds else { return nil }
            return end
        }
        guard let duration = episodeDurationSeconds,
              duration.isFinite,
              duration > 0 else {
            return nil
        }
        let start = chapters[index].startTimeSeconds
        guard duration >= start else { return nil }
        return duration
    }

    /// Chapter duration = end − start when end is known. `nil` when end cannot be derived
    /// (e.g. last chapter without episode duration).
    static func durationSeconds(
        in chapters: [PodcastChapter],
        atIndex index: Int,
        episodeDurationSeconds: Double?
    ) -> Double? {
        guard let end = endSeconds(in: chapters, atIndex: index, episodeDurationSeconds: episodeDurationSeconds),
              index >= 0, index < chapters.count else {
            return nil
        }
        let start = chapters[index].startTimeSeconds
        let duration = end - start
        guard duration.isFinite, duration >= 0 else { return nil }
        return duration
    }

    /// Remaining wall-clock time in the chapter at `index`: `max(0, end − position)`.
    /// `nil` when end is unknown. Does not require the chapter to be current — callers decide
    /// when to show remaining (typically only for the active chapter).
    static func remainingSeconds(
        in chapters: [PodcastChapter],
        atIndex index: Int,
        positionSeconds: Double,
        episodeDurationSeconds: Double?
    ) -> Double? {
        guard let end = endSeconds(in: chapters, atIndex: index, episodeDurationSeconds: episodeDurationSeconds) else {
            return nil
        }
        guard positionSeconds.isFinite else { return nil }
        return max(0, end - positionSeconds)
    }
}

/// Approximate listening time attributed to one episode from `playback.json`.
/// Played → `durationSeconds` when known (position is cleared on mark-played);
/// in-progress → `positionSeconds`. Not cumulative across rewinds / re-listens / speed.
enum ListeningTimeEstimate {
    static func seconds(for state: EpisodePlaybackState) -> Double {
        if state.isPlayed {
            if state.durationSeconds.isFinite, state.durationSeconds > 0 {
                return state.durationSeconds
            }
            return 0
        }
        if state.positionSeconds > 1 {
            return state.positionSeconds
        }
        return 0
    }

    static func hasMeaningfulData(_ state: EpisodePlaybackState) -> Bool {
        state.isPlayed || state.positionSeconds > 1
    }
}

/// Per-podcast rollup for Statistics (top list).
struct FeedListeningStats: Identifiable, Hashable {
    let id: UUID
    let feedTitle: String
    let playedEpisodeCount: Int
    let inProgressEpisodeCount: Int
    let approximateListenedSeconds: Double
}

/// Library-wide listening stats derived from `playback.json` (honest approximation).
struct ListeningStatistics: Hashable {
    var playedEpisodeCount: Int
    var inProgressEpisodeCount: Int
    var approximateListenedSeconds: Double
    var topPodcasts: [FeedListeningStats]

    var isEmpty: Bool {
        playedEpisodeCount == 0 && inProgressEpisodeCount == 0
    }

    static let empty = ListeningStatistics(
        playedEpisodeCount: 0,
        inProgressEpisodeCount: 0,
        approximateListenedSeconds: 0,
        topPodcasts: []
    )
}

/// Per-podcast rollup for Echo (year in review).
struct EchoFeedStats: Identifiable, Hashable {
    let id: UUID
    let feedTitle: String
    let playedEpisodeCount: Int
    let approximateListenedSeconds: Double
}

/// Calendar-year summary from playback / favorites (honest approximation; same limits as Statistics).
struct EchoYearSummary: Hashable {
    /// Calendar year (e.g. 2026).
    var year: Int
    /// Episodes with `isPlayed` whose `lastPlayedAt` falls in this year.
    var playedEpisodeCount: Int
    var approximateListenedSeconds: Double
    var topPodcasts: [EchoFeedStats]
    /// Favorites whose favorited-at timestamp falls in this year (`favorites.json`).
    var favoritesCountThisYear: Int
    /// All currently starred episodes (any year).
    var favoritesTotalCount: Int

    var isEmpty: Bool {
        playedEpisodeCount == 0 && approximateListenedSeconds <= 0 && favoritesCountThisYear == 0
    }

    static func empty(year: Int) -> EchoYearSummary {
        EchoYearSummary(
            year: year,
            playedEpisodeCount: 0,
            approximateListenedSeconds: 0,
            topPodcasts: [],
            favoritesCountThisYear: 0,
            favoritesTotalCount: 0
        )
    }
}
