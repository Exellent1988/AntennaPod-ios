import Foundation

/// Chapter marker from feed (Podlove Simple Chapters / Podcast Index), remote JSON, or local media-file tags.
struct PodcastChapter: Identifiable, Hashable, Codable {
    var id: String { "\(startTimeSeconds)|\(title)" }
    var title: String
    /// Start offset from episode beginning.
    var startTimeSeconds: Double
    var href: String?
    /// Optional chapter artwork from feed PSC `image`/`img` or Podcast Index JSON `img`/`image`.
    /// Never invent; media-file chapters leave this nil.
    var imageUrl: String?

    init(title: String, startTimeSeconds: Double, href: String? = nil, imageUrl: String? = nil) {
        self.title = title
        self.startTimeSeconds = startTimeSeconds
        self.href = href
        self.imageUrl = imageUrl
    }

    /// http(s) chapter artwork URL from feed/JSON `imageUrl` only. Nil when missing / non-http(s).
    /// List thumbnails: show when present; hide when nil — never invent / never fall back to episode art.
    /// Full player large cover: prefer this URL for the current chapter; fall back to episode/feed art when nil/fail.
    var displayImageURL: URL? {
        guard let imageUrl else { return nil }
        let trimmed = imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// http(s) chapter link from feed PSC `href`/`url` or Podcast Index JSON `url` only.
    /// Nil when missing / non-http(s). UI Open control when present — never invent.
    var displayLinkURL: URL? {
        guard let href else { return nil }
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
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

    /// Trimmed raw `pubdate` from the feed. Hidden when absent or blank — never reformat or invent.
    var displayPubDate: String? {
        guard let pubDate else { return nil }
        let trimmed = pubDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed raw MIME type from the feed `type` attribute. Hidden when absent or blank.
    var displayType: String? {
        guard let type else { return nil }
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Feed-provided trailer byte length using the app's existing localized file-size caption.
    /// Hidden when missing or non-positive; no size is invented.
    var displayLengthLabel: String? {
        guard let length, length > 0 else { return nil }
        return DownloadStorageUsage.formatBytes(length)
    }

    /// http(s) media URL from feed `url` only. Nil when missing / non-http(s).
    /// A space in the feed URL is percent-encoded (`EpisodeMediaURL`) so Play, Open,
    /// Copy, and Share still appear. `URL(string:)` alone drops that URL.
    var mediaURL: URL? {
        guard let parsed = EpisodeMediaURL.url(from: url) else { return nil }
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

    /// Prefix of `asPlaybackEpisode` ids: `podcast-trailer:<feedUUID>:`.
    /// Unsubscribe and feed-scoped download deletion match this even when the media URL changed.
    static func playbackEpisodeIdPrefix(feedId: UUID) -> String {
        "podcast-trailer:\(feedId.uuidString):"
    }

    /// Synthetic episode for `PlaybackService.play` — not added to `PodcastFeed.episodes`.
    /// Id embeds feed UUID so Now Playing can resolve artwork/title via `feed(containingEpisodeId:)`.
    func asPlaybackEpisode(feedId: UUID) -> PodcastEpisode? {
        guard let media = mediaURL else { return nil }
        let titleText = displayTitle ?? title
        return PodcastEpisode(
            id: "\(Self.playbackEpisodeIdPrefix(feedId: feedId))\(media.absoluteString)",
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
            people: [],
            locations: []
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

    /// Trimmed non-empty group when the feed set `group`. Hidden when missing — never invent "cast".
    var displayGroup: String? {
        guard let group else { return nil }
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
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
                group: person.displayGroup,
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


/// Podcast Index `podcast:location` — feed-provided place name only (never invent / never geocode names).
/// Element text = human-readable name (required to keep); optional `geo` (RFC5870 geo URI), `osm`, `rel`.
/// Open in Maps only when `geo` parses to lat,lon — never geocode from name alone.
struct PodcastLocation: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields (names can repeat).
    var id: String { "\(name)|\(geo ?? "")|\(osm ?? "")|\(rel ?? "")" }
    /// Human-readable location from element text (required by Podcast Index; may be truncated ~128 chars).
    var name: String
    /// Optional `geo` attribute as provided (e.g. `geo:30.2672,97.7431`). Nil when absent — never invent.
    var geo: String?
    /// Optional OpenStreetMap id from `osm` (e.g. `R113314`). Nil when absent — never invent / never fetch OSM.
    var osm: String?
    /// Optional `rel` attribute (`subject` / `creator`). Nil when absent — never invent default.
    var rel: String?

    init(name: String, geo: String? = nil, osm: String? = nil, rel: String? = nil) {
        self.name = name
        self.geo = geo
        self.osm = osm
        self.rel = rel
    }

    /// Trimmed non-empty name. Nil when blank.
    var displayName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty `rel` when the feed set it. Hidden when missing — never invent "subject".
    var displayRel: String? {
        guard let rel else { return nil }
        let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty `osm` when the feed set it. Hidden when missing — never invent.
    var displayOsm: String? {
        guard let osm else { return nil }
        let trimmed = osm.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty `geo` when the feed set it. Hidden when missing — never invent / never geocode.
    var displayGeo: String? {
        guard let geo else { return nil }
        let trimmed = geo.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parsed latitude/longitude from feed `geo` only (RFC5870 `geo:lat,lon`[,alt][;params]).
    /// Nil when missing / unparsable — **never geocode** from name.
    var coordinates: (latitude: Double, longitude: Double)? {
        PodcastLocationGeoParsing.coordinates(from: geo)
    }

    /// Apple Maps URL when feed `geo` parses to lat,lon. Uses place name as pin label when non-empty.
    /// Nil when no coordinates — never invent a Maps URL from name alone.
    var appleMapsURL: URL? {
        guard let coords = coordinates else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "ll", value: "\(coords.latitude),\(coords.longitude)")
        ]
        if let label = displayName {
            items.append(URLQueryItem(name: "q", value: label))
        }
        components?.queryItems = items
        return components?.url
    }
}

/// Parse Podcast Index / RFC5870 `geo:` URIs for display / Maps only — never invent coordinates.
enum PodcastLocationGeoParsing {
    /// Returns lat/lon when `geo` is a usable `geo:lat,lon` URI; otherwise nil.
    static func coordinates(from raw: String?) -> (latitude: Double, longitude: Double)? {
        guard let raw else { return nil }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("geo:") {
            s = String(s.dropFirst(4))
        }
        // Drop `;crs=…` / `;u=…` parameters — coordinates are before the first `;`.
        if let semi = s.firstIndex(of: ";") {
            s = String(s[..<semi])
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = s.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count >= 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              lat.isFinite, lon.isFinite,
              (-90...90).contains(lat),
              (-180...180).contains(lon) else {
            return nil
        }
        return (lat, lon)
    }
}

/// Display helpers for `podcast:location` lists (channel or item). Feed-provided only.
enum PodcastLocationDisplay {
    /// Soft UI cap — show first N, honesty footnote when more exist in the feed.
    static let displayCap = 20

    /// Non-empty named locations in feed order (no invented entries / no geocoding).
    static func valid(_ locations: [PodcastLocation]) -> [PodcastLocation] {
        locations.compactMap { location in
            guard let name = location.displayName else { return nil }
            return PodcastLocation(
                name: name,
                geo: location.displayGeo,
                osm: location.displayOsm,
                rel: location.displayRel
            )
        }
    }

    /// First `displayCap` locations + whether the feed listed more.
    static func capped(_ locations: [PodcastLocation]) -> (shown: [PodcastLocation], truncated: Bool) {
        let list = valid(locations)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Pasteboard / ShareLink text: the feed-provided name plus optional raw attributes.
    /// Keep this separate from the Maps URL: copying a location never invents coordinates or geocodes.
    static func copyText(_ location: PodcastLocation) -> String {
        guard let name = location.displayName else { return "" }
        var lines = [name]
        if let geo = location.displayGeo {
            lines.append("geo: \(geo)")
        }
        if let osm = location.displayOsm {
            lines.append("osm: \(osm)")
        }
        if let rel = location.displayRel {
            lines.append("rel: \(rel)")
        }
        return lines.joined(separator: "\n")
    }
}


/// Podcast Index `podcast:socialInteract` — feed-provided discussion root only (never invent URLs).
/// Required: `protocol` + `uri` (or `url`); optional `accountId` / `priority` (lower = higher priority).
/// **openURL / Share / Copy only** — no in-app Fediverse client, no posting / API. `protocol=disabled` → no Discuss UI.
struct PodcastSocialInteract: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String { "\(protocolName)|\(uri)|\(accountId ?? "")|\(priority.map(String.init) ?? "")" }
    /// Protocol name from feed (`activitypub`, `twitter`, …). Stored as `protocolName` because `protocol` is reserved.
    var protocolName: String
    /// Root-post URI/URL string from `uri` / `url` (or element text when it is http(s)).
    var uri: String
    /// Optional account id on the commenting platform (e.g. `@user@host`).
    var accountId: String?
    /// Optional priority — lower integer = higher priority when several tags exist. Nil when absent.
    var priority: Int?

    init(protocolName: String, uri: String, accountId: String? = nil, priority: Int? = nil) {
        self.protocolName = protocolName
        self.uri = uri
        self.accountId = accountId
        self.priority = priority
    }

    /// True when feed sets `protocol` to `disabled` (opt out of public comments) — hide Discuss.
    var isDisabled: Bool {
        protocolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disabled"
    }

    /// Trimmed non-empty protocol when usable (not disabled / not blank). Nil when missing.
    var displayProtocol: String? {
        let trimmed = protocolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased() == "disabled" { return nil }
        return trimmed
    }

    /// Trimmed non-empty accountId when the feed set it. Hidden when missing — never invent.
    var displayAccountId: String? {
        guard let accountId else { return nil }
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) discussion URL from feed `uri` only. Nil when missing / non-http(s) — never invent.
    var discussionURL: URL? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = URL(string: trimmed) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }
}

/// Display helpers for `podcast:socialInteract` lists (channel or item). Feed-provided only; openURL / Share / Copy only.
enum PodcastSocialInteractDisplay {
    /// Soft UI cap — show first N after priority sort; honesty footnote when more exist in the feed.
    static let displayCap = 20

    /// Openable (http(s) URI + non-disabled protocol) entries, sorted by priority (lower first; nil last), feed order for ties.
    /// No invented URLs / no Fediverse client.
    static func valid(_ items: [PodcastSocialInteract]) -> [PodcastSocialInteract] {
        var indexed: [(Int, PodcastSocialInteract)] = []
        for (index, item) in items.enumerated() {
            guard !item.isDisabled else { continue }
            guard let proto = item.displayProtocol else { continue }
            let uri = item.uri.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uri.isEmpty else { continue }
            let candidate = PodcastSocialInteract(
                protocolName: proto,
                uri: uri,
                accountId: item.displayAccountId,
                priority: item.priority
            )
            guard candidate.discussionURL != nil else { continue }
            indexed.append((index, candidate))
        }
        // Sort by priority ascending (nil last), stable by original feed order.
        indexed.sort { lhs, rhs in
            let lp = lhs.1.priority
            let rp = rhs.1.priority
            switch (lp, rp) {
            case let (l?, r?) where l != r:
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.0 < rhs.0
            }
        }
        return indexed.map(\.1)
    }

    /// Highest-priority openable socialInteract (lowest priority Int). Nil when none.
    static func preferred(_ items: [PodcastSocialInteract]) -> PodcastSocialInteract? {
        valid(items).first
    }

    /// First `displayCap` after priority sort + whether the feed listed more openable entries.
    static func capped(_ items: [PodcastSocialInteract]) -> (shown: [PodcastSocialInteract], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }
}


/// Podcast Index `podcast:value` + nested `podcast:valueRecipient` — Value4Value metadata only.
/// **Display-only:** this app does **not** send Lightning / wallet payments, stream sats, or call payment APIs.
/// Feed-provided only — never invent recipients or payment addresses as actionable sends.
struct PodcastValue: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String {
        let rec = recipients.map(\.id).joined(separator: ";")
        return "\(type)|\(method)|\(suggested ?? "")|\(rec)"
    }
    /// Value layer / cryptocurrency slug from feed (`lightning`, `webmonetization`, …).
    var type: String
    /// Transport method from feed (`keysend`, `ILP`, …).
    var method: String
    /// Optional suggested amount string as provided (informational only — never used to send).
    var suggested: String?
    /// Nested `podcast:valueRecipient` entries (may be empty after parse filtering).
    var recipients: [PodcastValueRecipient]

    init(type: String, method: String, suggested: String? = nil, recipients: [PodcastValueRecipient] = []) {
        self.type = type
        self.method = method
        self.suggested = suggested
        self.recipients = recipients
    }

    /// Trimmed non-empty feed `suggested` when set. Informational only — never invent / never use to send payments.
    var displaySuggested: String? {
        guard let suggested else { return nil }
        let trimmed = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One `podcast:valueRecipient` — type, address, split required by Podcast Index; name recommended; fee optional.
struct PodcastValueRecipient: Identifiable, Hashable, Codable {
    var id: String { "\(name ?? "")|\(type)|\(address)|\(split)|\(fee.map(String.init) ?? "")" }
    /// Optional display name from feed. Nil when absent — never invent.
    var name: String?
    /// Address type slug (`node`, `lnaddress`, …).
    var type: String
    /// Receiving address / payment pointer / node pubkey as provided.
    var address: String
    /// Share count from feed `split` (not necessarily a percentage — UI may derive %).
    var split: Int
    /// Optional `fee` attribute. Nil when absent (spec default false).
    var fee: Bool?

    init(name: String? = nil, type: String, address: String, split: Int, fee: Bool? = nil) {
        self.name = name
        self.type = type
        self.address = address
        self.split = split
        self.fee = fee
    }

    /// Trimmed non-empty name when the feed set it.
    var displayName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty recipient type.
    var displayType: String? {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty address. Nil when blank.
    var displayAddress: String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when feed set `fee` to true/yes.
    var isFee: Bool { fee == true }

    /// http(s) recipient page from feed `address` only. Nil for lightning node / lnaddress / other non-http(s).
    /// Never invent payment URLs — openURL only when the address itself is http(s).
    var browserURL: URL? {
        guard let trimmed = displayAddress, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

/// Flattened display row: recipient + parent `podcast:value` type/method + optional split %.
struct PodcastValueRecipientRow: Identifiable, Hashable {
    var id: String { "\(valueType)|\(valueMethod)|\(recipient.id)|\(splitPercent.map(String.init) ?? "")" }
    var recipient: PodcastValueRecipient
    var valueType: String
    var valueMethod: String
    /// Percentage of this block’s total split shares (rounded). Nil when total ≤ 0.
    var splitPercent: Int?

    var displayName: String? { recipient.displayName }
    var displayRecipientType: String? { recipient.displayType }
    var displayAddress: String? { recipient.displayAddress }
    var browserURL: URL? { recipient.browserURL }
    var isFee: Bool { recipient.isFee }
    var split: Int { recipient.split }

    /// Compact type/method caption for UI (e.g. `lightning / keysend`).
    var typeMethodCaption: String {
        "\(valueType) / \(valueMethod)"
    }
}

/// Display helpers for `podcast:value` / valueRecipient lists (channel or item). Feed-provided only; no payments.
enum PodcastValueDisplay {
    /// Soft UI cap — show first N flattened recipients; honesty footnote when more exist.
    static let displayCap = 20

    /// Flatten valid recipients from value blocks (type+method+address+split required). Feed order.
    /// Computes split % per block from that block’s total shares. No invented recipients / no payment sends.
    static func valid(_ values: [PodcastValue]) -> [PodcastValueRecipientRow] {
        var rows: [PodcastValueRecipientRow] = []
        for value in values {
            let vType = value.type.trimmingCharacters(in: .whitespacesAndNewlines)
            let vMethod = value.method.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vType.isEmpty, !vMethod.isEmpty else { continue }
            let cleaned: [PodcastValueRecipient] = value.recipients.compactMap { rec in
                guard let rType = rec.displayType, let addr = rec.displayAddress, rec.split >= 0 else { return nil }
                return PodcastValueRecipient(
                    name: rec.displayName,
                    type: rType,
                    address: addr,
                    split: rec.split,
                    fee: rec.fee
                )
            }
            guard !cleaned.isEmpty else { continue }
            let total = cleaned.reduce(0) { $0 + max(0, $1.split) }
            for rec in cleaned {
                let pct: Int? = total > 0 ? Int((Double(rec.split) * 100.0 / Double(total)).rounded()) : nil
                rows.append(
                    PodcastValueRecipientRow(
                        recipient: rec,
                        valueType: vType,
                        valueMethod: vMethod,
                        splitPercent: pct
                    )
                )
            }
        }
        return rows
    }

    /// First `displayCap` flattened recipients + whether more exist in the feed.
    static func capped(_ values: [PodcastValue]) -> (shown: [PodcastValueRecipientRow], truncated: Bool) {
        let list = valid(values)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Feed-provided `suggested` strings from value blocks that also contribute at least one valid recipient.
    /// Once per block, feed order. Hide when missing — never invent a suggested amount.
    static func displaySuggestedList(_ values: [PodcastValue]) -> [(id: String, text: String)] {
        var out: [(id: String, text: String)] = []
        for value in values {
            guard let text = value.displaySuggested else { continue }
            let vType = value.type.trimmingCharacters(in: .whitespacesAndNewlines)
            let vMethod = value.method.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vType.isEmpty, !vMethod.isEmpty else { continue }
            let hasRecipient = value.recipients.contains { rec in
                rec.displayType != nil && rec.displayAddress != nil && rec.split >= 0
            }
            guard hasRecipient else { continue }
            out.append((value.id, text))
        }
        return out
    }
}





/// Podcast Index `podcast:source` under `podcast:alternateEnclosure`.
/// Required `uri`; optional `contentType` when transport MIME differs from the media type.
/// Feed-provided only — never invent URIs.
struct PodcastAlternateSource: Identifiable, Hashable, Codable {
    var id: String { "\(uri)|\(contentType ?? "")" }
    /// Required URI from the feed (`https://…`, `ipfs://…`, torrent URL, …).
    var uri: String
    /// Optional transport MIME (e.g. `application/x-bittorrent`) when it differs from parent `type`.
    var contentType: String?

    init(uri: String, contentType: String? = nil) {
        self.uri = uri
        self.contentType = contentType
    }

    /// Trimmed non-empty URI. Nil when blank.
    var displayURI: String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty contentType when the feed set it.
    var displayContentType: String? {
        guard let contentType else { return nil }
        let trimmed = contentType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) openable URL from feed `uri` only. Nil for ipfs / magnet / other schemes — Copy / Share instead.
    /// Never invent URLs — openURL only when the URI itself is http(s).
    /// A space in the feed URI is percent-encoded (`EpisodeMediaURL`) so Play and Open URL still appear.
    /// `URL(string:)` alone drops that URI.
    var browserURL: URL? {
        guard let parsed = EpisodeMediaURL.url(from: displayURI) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// http(s) URI suitable for in-app `PlaybackService` / AVPlayer. Same as `browserURL`.
    /// Nil for ipfs / magnet / other schemes — those stay Copy / Share outside the player.
    var playableMediaURL: URL? { browserURL }
}

/// Podcast Index `podcast:alternateEnclosure` — alternate / companion media for an item.
/// Required `type` + ≥1 `podcast:source`. Optional length/bitrate/height/lang/title/rel/codecs/default.
/// http(s) sources can **Play** the same episode via `PlaybackService` (`preferredMediaURL`);
/// ipfs / magnet stay Copy / Share. Feed-provided only — never invent enclosures.
struct PodcastAlternateEnclosure: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields + sources.
    var id: String {
        let src = sources.map(\.id).joined(separator: ";")
        return "\(type)|\(title ?? "")|\(bitrate.map { String($0) } ?? "")|\(length.map(String.init) ?? "")|\(lang ?? "")|\(rel ?? "")|\(src)"
    }
    /// Required MIME type of the media asset (`audio/mpeg`, `video/mp4`, …).
    var type: String
    /// Recommended file length in bytes when the feed provides it.
    var length: Int64?
    /// Optional average encoding bitrate in bits per second.
    var bitrate: Double?
    /// Optional video height in pixels.
    var height: Int?
    /// Optional IETF language tag (BCP 47).
    var lang: String?
    /// Optional human-readable label (Podcast Index suggests ≤32 characters).
    var title: String?
    /// Optional grouping / relation (e.g. commentary). Nil or `default` = alternative to the main enclosure.
    var rel: String?
    /// Optional RFC 6381 codecs string.
    var codecs: String?
    /// Optional `default` attribute — preferred / same as RSS enclosure when true.
    var isDefault: Bool?
    /// Nested `podcast:source` entries (at least one required by the namespace).
    var sources: [PodcastAlternateSource]

    init(
        type: String,
        length: Int64? = nil,
        bitrate: Double? = nil,
        height: Int? = nil,
        lang: String? = nil,
        title: String? = nil,
        rel: String? = nil,
        codecs: String? = nil,
        isDefault: Bool? = nil,
        sources: [PodcastAlternateSource] = []
    ) {
        self.type = type
        self.length = length
        self.bitrate = bitrate
        self.height = height
        self.lang = lang
        self.title = title
        self.rel = rel
        self.codecs = codecs
        self.isDefault = isDefault
        self.sources = sources
    }

    /// Trimmed non-empty MIME type.
    var displayType: String? {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty title when the feed set it.
    var displayTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty lang when the feed set it.
    var displayLang: String? {
        guard let lang else { return nil }
        let trimmed = lang.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty rel when set and not the literal `default` (spec default grouping).
    var displayRel: String? {
        guard let rel else { return nil }
        let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased() == "default" { return nil }
        return trimmed
    }

    /// Trimmed non-empty codecs when the feed set it.
    var displayCodecs: String? {
        guard let codecs else { return nil }
        let trimmed = codecs.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when feed set `default` to true/yes/1.
    var markedDefault: Bool { isDefault == true }

    /// Sources with a non-empty URI (feed order).
    var validSources: [PodcastAlternateSource] {
        sources.compactMap { src in
            guard let uri = src.displayURI else { return nil }
            return PodcastAlternateSource(uri: uri, contentType: src.displayContentType)
        }
    }
}

/// Display helpers for item `podcast:alternateEnclosure` lists. Feed-provided only.
/// http(s) → Play (same episode) + Open URL + Copy / Share; other schemes → Copy / Share.
enum PodcastAlternateEnclosureDisplay {
    /// Soft UI cap — show first N after feed order; honesty footnote when more exist.
    static let displayCap = 20

    /// Enclosures with required type + ≥1 source URI. Feed order. No invented entries.
    static func valid(_ items: [PodcastAlternateEnclosure]) -> [PodcastAlternateEnclosure] {
        items.compactMap { item in
            guard let mime = item.displayType else { return nil }
            let cleanedSources = item.validSources
            guard !cleanedSources.isEmpty else { return nil }
            return PodcastAlternateEnclosure(
                type: mime,
                length: (item.length ?? 0) > 0 ? item.length : nil,
                bitrate: (item.bitrate ?? 0) > 0 ? item.bitrate : nil,
                height: (item.height ?? 0) > 0 ? item.height : nil,
                lang: item.displayLang,
                title: item.displayTitle,
                rel: item.displayRel,
                codecs: item.displayCodecs,
                isDefault: item.isDefault,
                sources: cleanedSources
            )
        }
    }

    /// First `displayCap` + whether the feed listed more valid alternate enclosures.
    static func capped(_ items: [PodcastAlternateEnclosure]) -> (shown: [PodcastAlternateEnclosure], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Human bitrate label from bits-per-second (e.g. `128 kbps`). Nil when missing / non-positive.
    static func bitrateLabel(_ bitrate: Double?) -> String? {
        guard let bitrate, bitrate.isFinite, bitrate > 0 else { return nil }
        if bitrate >= 1_000_000 {
            let mbps = bitrate / 1_000_000
            let text = mbps == floor(mbps) ? String(format: "%.0f", mbps) : String(format: "%.1f", mbps)
            return "\(text) Mbps"
        }
        if bitrate >= 1000 {
            let kbps = bitrate / 1000
            let text = kbps == floor(kbps) ? String(format: "%.0f", kbps) : String(format: "%.1f", kbps)
            return "\(text) kbps"
        }
        return "\(Int(bitrate.rounded())) bps"
    }

    /// File size via `DownloadStorageUsage.formatBytes` when length > 0.
    static func lengthLabel(_ length: Int64?) -> String? {
        guard let length, length > 0 else { return nil }
        return DownloadStorageUsage.formatBytes(length)
    }

    /// Localized language name when possible, else raw BCP 47 tag.
    static func languageLabel(_ lang: String?) -> String? {
        guard let lang, !lang.isEmpty else { return nil }
        let code = lang.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let name = Locale.current.localizedString(forLanguageCode: code)
            ?? Locale.current.localizedString(forIdentifier: code)
        if let name, !name.isEmpty { return name }
        return code
    }

    /// Height caption for video (`720p`) when height > 0.
    static func heightLabel(_ height: Int?) -> String? {
        guard let height, height > 0 else { return nil }
        return "\(height)p"
    }
}


/// Podcast Index `podcast:soundbite` — short highlight within an item’s enclosure.
/// Required `startTime` + `duration` (seconds, float). Optional element text = title.
/// **Not a separate clip player:** UI may **Play soundbite** (seek to `startTime`, auto-pause at
/// `startTime + duration` via PlaybackService) or Copy / Share the displayed title and times. Feed-provided only — never invent.
struct PodcastSoundbite: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String {
        "\(startTimeSeconds)|\(durationSeconds)|\(title ?? "")"
    }
    /// Required start offset in seconds from the beginning of the episode enclosure.
    var startTimeSeconds: Double
    /// Required soundbite length in seconds.
    var durationSeconds: Double
    /// Optional human-readable title (element text). Nil when absent / blank.
    var title: String?

    init(startTimeSeconds: Double, durationSeconds: Double, title: String? = nil) {
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.title = title
    }

    /// Trimmed non-empty title when the feed set it.
    var displayTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when startTime is finite and ≥ 0 and duration is finite and > 0 (Podcast Index required attrs).
    var isValid: Bool {
        startTimeSeconds.isFinite && startTimeSeconds >= 0
            && durationSeconds.isFinite && durationSeconds > 0
    }
}

/// Display helpers for item `podcast:soundbite` lists. Feed-provided only; play/seek via existing PlaybackService.
enum PodcastSoundbiteDisplay {
    /// Soft UI cap — show first N after feed order; honesty footnote when more exist.
    static let displayCap = 20

    /// Soundbites with required startTime (≥0) + duration (>0). Feed order. No invented entries / no separate clip player.
    static func valid(_ items: [PodcastSoundbite]) -> [PodcastSoundbite] {
        items.compactMap { item in
            guard item.isValid else { return nil }
            return PodcastSoundbite(
                startTimeSeconds: item.startTimeSeconds,
                durationSeconds: item.durationSeconds,
                title: item.displayTitle
            )
        }
    }

    /// First `displayCap` + whether the feed listed more valid soundbites.
    static func capped(_ items: [PodcastSoundbite]) -> (shown: [PodcastSoundbite], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Human start / duration (`m:ss` / `h:mm:ss`), matching full-player / share formatters.
    static func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Exact displayed start caption for a feed-provided soundbite.
    static func startCaption(_ item: PodcastSoundbite) -> String {
        String(localized: "Start \(formatSeconds(item.startTimeSeconds))")
    }

    /// Exact displayed duration caption for a feed-provided soundbite.
    static func durationCaption(_ item: PodcastSoundbite) -> String {
        String(localized: "Duration \(formatSeconds(item.durationSeconds))")
    }

    /// Caption `start · duration` retained for callers that use the compact summary form.
    static func timeCaption(_ item: PodcastSoundbite) -> String {
        "\(formatSeconds(item.startTimeSeconds)) · \(formatSeconds(item.durationSeconds))"
    }

    /// Plain-text summary matching the displayed title and separate start/duration captions.
    static func copyText(_ item: PodcastSoundbite) -> String {
        var lines = [startCaption(item), durationCaption(item)]
        if let title = item.displayTitle {
            lines.insert(title, at: 0)
        }
        return lines.joined(separator: "\n")
    }
}





/// Podcast Index `podcast:txt` — free-form text for a podcast or episode.
/// Optional `purpose` attribute (e.g. transcript, peertube, verify, twitter) + element text.
/// **Display-only:** Copy text; Share when copyable (prefers http(s)); Open when value looks like http(s). No Social / Matrix / special clients.
/// Feed-provided only — never invent purposes or text. Purpose shown as the raw feed string when set.
struct PodcastTxt: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String { "\(purpose ?? "")|\(text)" }
    /// Optional `purpose` attribute as provided by the feed. Nil when absent — never invent.
    var purpose: String?
    /// Element text content (required non-empty to keep).
    var text: String

    init(purpose: String? = nil, text: String) {
        self.purpose = purpose
        self.text = text
    }

    /// Trimmed non-empty purpose when the feed set it. Hidden when missing — never invent labels.
    var displayPurpose: String? {
        guard let purpose else { return nil }
        let trimmed = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty text body. Nil when blank.
    var displayText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) URL when the text body looks like one. Nil otherwise — never invent.
    var openURL: URL? {
        guard let body = displayText else { return nil }
        guard let parsed = URL(string: body) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }
}

/// Display helpers for `podcast:txt` lists (channel or item). Feed-provided only; Copy + Share + optional Open.
enum PodcastTxtDisplay {
    /// Soft UI cap — show first N after feed order; honesty footnote when more exist.
    static let displayCap = 20

    /// Entries with non-empty text. Feed order. No invented purposes / no special clients.
    static func valid(_ items: [PodcastTxt]) -> [PodcastTxt] {
        items.compactMap { item in
            guard let body = item.displayText else { return nil }
            return PodcastTxt(purpose: item.displayPurpose, text: body)
        }
    }

    /// First `displayCap` + whether the feed listed more valid txt entries.
    static func capped(_ items: [PodcastTxt]) -> (shown: [PodcastTxt], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Pasteboard line: optional purpose + text body.
    static func copyText(_ item: PodcastTxt) -> String {
        let body = item.displayText ?? item.text
        if let purpose = item.displayPurpose {
            return "\(purpose): \(body)"
        }
        return body
    }
}


/// Podcast Index `podcast:license` — license identifier text and/or optional `url` attribute.
/// Channel and/or item. Namespace count is typically single; we still store a list and cap display.
/// **Display-only:** show license text; Open http(s) URL / Copy. **No DRM enforcement.**
/// Feed-provided only — never invent licenses or URLs.
struct PodcastLicense: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String { "\(url ?? "")|\(text)" }
    /// Optional `url` attribute pointing at the full license text. Nil when absent — never invent.
    var url: String?
    /// Element text (license identifier / abbreviation). May be empty when only url is present.
    var text: String

    init(url: String? = nil, text: String) {
        self.url = url
        self.text = text
    }

    /// Trimmed non-empty license text when the feed set it. Hidden when blank.
    var displayText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty `url` attribute string. Nil when blank — never invent.
    var displayUrlString: String? {
        guard let url else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) URL from the `url` attribute when valid. Nil otherwise — never invent.
    var openURL: URL? {
        guard let trimmed = displayUrlString, let parsed = URL(string: trimmed) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }
}

/// Display helpers for `podcast:license` lists (channel or item). Feed-provided only;
/// distinct Copy/Share license text + Copy/Share license URL + optional Open http(s).
enum PodcastLicenseDisplay {
    /// Soft UI cap — namespace is typically single; show first N if a feed lists more + honesty footnote.
    static let displayCap = 5

    /// Entries with non-empty text and/or a non-empty url attribute. Feed order. No invented licenses.
    static func valid(_ items: [PodcastLicense]) -> [PodcastLicense] {
        items.compactMap { item in
            let body = item.displayText
            let urlString = item.displayUrlString
            guard body != nil || urlString != nil else { return nil }
            return PodcastLicense(url: urlString, text: body ?? "")
        }
    }

    /// First `displayCap` + whether the feed listed more valid license entries.
    static func capped(_ items: [PodcastLicense]) -> (shown: [PodcastLicense], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Combined pasteboard line: license text + optional URL string (helper; UI uses distinct actions).
    static func copyText(_ item: PodcastLicense) -> String {
        let body = item.displayText
        let url = item.displayUrlString
        switch (body, url) {
        case let (b?, u?):
            return "\(b)\n\(u)"
        case let (b?, nil):
            return b
        case let (nil, u?):
            return u
        default:
            return item.text
        }
    }
}




/// Podcast Index `podcast:images` (deprecated srcset) / `podcast:image` (href + optional width).
/// Channel and/or item. Stores URL + optional pixel width (and optional height/alt/purpose when present).
/// **Feed-provided only** — never invent URLs or sizes. Cap ~10 for display/storage honesty.
/// Prefer one higher-res http(s) URL for Feed detail / Full player / Now Playing artwork; do **not** download all variants eagerly.
struct PodcastImageVariant: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String { "\(url)|\(width.map(String.init) ?? "")|\(height.map(String.init) ?? "")|\(purpose ?? "")" }
    /// Image URL from `podcast:image` href / `podcast:images` srcset entry. Required non-empty to keep.
    var url: String
    /// Pixel width from srcset `Nw` descriptor or `width` attribute when the feed provides it. Nil when absent — never invent.
    var width: Int?
    /// Optional `height` attribute on `podcast:image`. Nil when absent — never invent.
    var height: Int?
    /// Optional `alt` attribute. Nil when absent — never invent.
    var alt: String?
    /// Optional `purpose` attribute (space-separated tokens). Nil when absent — never invent.
    var purpose: String?

    init(
        url: String,
        width: Int? = nil,
        height: Int? = nil,
        alt: String? = nil,
        purpose: String? = nil
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.alt = alt
        self.purpose = purpose
    }

    /// Trimmed non-empty URL string when present.
    var displayURLString: String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) URL when valid. Nil otherwise — never invent.
    var openURL: URL? {
        guard let raw = displayURLString, let parsed = URL(string: raw) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// Trimmed non-empty alt when the feed set it.
    var displayAlt: String? {
        guard let alt else { return nil }
        let trimmed = alt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty purpose when the feed set it (raw feed string).
    var displayPurpose: String? {
        guard let purpose else { return nil }
        let trimmed = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Width label for UI when known (e.g. "1500w"). Nil when width absent — never invent.
    var displayWidthLabel: String? {
        guard let width, width > 0 else { return nil }
        return "\(width)w"
    }

    /// Height label for UI when known (e.g. "720p"). Nil when height absent — never invent.
    var displayHeightLabel: String? {
        guard let height, height > 0 else { return nil }
        return "\(height)p"
    }
}

/// Display helpers for `podcast:images` / `podcast:image` lists (channel or item).
/// Feed-provided only; Open / Copy / Share; prefer one higher-res http(s) URL for artwork — never download all eagerly.
enum PodcastImagesDisplay {
    /// Soft UI / storage cap — show first N after feed order; honesty footnote when more exist.
    static let displayCap = 10

    /// Soft upper bound when picking a single artwork URL (avoid pathological huge assets when smaller widths exist).
    static let preferredMaxWidth = 3000

    /// http(s) variants only, feed order. No invented URLs; non-http(s) values are not artwork candidates.
    static func valid(_ items: [PodcastImageVariant]) -> [PodcastImageVariant] {
        items.compactMap { item in
            guard let open = item.openURL else { return nil }
            return PodcastImageVariant(
                url: open.absoluteString,
                width: item.width.flatMap { $0 > 0 ? $0 : nil },
                height: item.height.flatMap { $0 > 0 ? $0 : nil },
                alt: item.displayAlt,
                purpose: item.displayPurpose
            )
        }
    }

    /// First `displayCap` + whether the feed listed more valid image variants.
    static func capped(_ items: [PodcastImageVariant]) -> (shown: [PodcastImageVariant], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Pick one reasonable http(s) artwork URL: largest width ≤ `preferredMaxWidth`, else largest width, else first.
    /// Nil when no valid variants — callers fall back to `itunes:image` / RSS `<image>` / Atom logo path.
    static func preferredArtworkURL(_ items: [PodcastImageVariant]) -> String? {
        let list = valid(items)
        guard !list.isEmpty else { return nil }
        let withWidth = list.compactMap { item -> (PodcastImageVariant, Int)? in
            guard let w = item.width, w > 0 else { return nil }
            return (item, w)
        }
        if !withWidth.isEmpty {
            let underCap = withWidth.filter { $0.1 <= preferredMaxWidth }
            let pool = underCap.isEmpty ? withWidth : underCap
            return pool.max(by: { $0.1 < $1.1 })?.0.url
        }
        return list.first?.url
    }

    /// Pasteboard line: optional width/height + URL (+ optional purpose/alt).
    static func copyText(_ item: PodcastImageVariant) -> String {
        var parts: [String] = []
        if let w = item.displayWidthLabel {
            parts.append(w)
        }
        if let h = item.displayHeightLabel {
            parts.append(h)
        }
        if let purpose = item.displayPurpose {
            parts.append(purpose)
        }
        parts.append(item.displayURLString ?? item.url)
        if let alt = item.displayAlt {
            parts.append(alt)
        }
        return parts.joined(separator: " · ")
    }
}

/// Podcast Index `podcast:remoteItem` under channel `podcast:podroll` or `podcast:publisher`.
/// Attributes: `feedGuid` (required by namespace), optional `feedUrl` / `title` / `medium` / `itemGuid`.
/// **Display-only:** title + url/guid; Open http(s) feed URL / Copy / Subscribe via existing preview when URL present.
/// Feed-provided only — never invent recommendations/publishers. itemGuid is uncommon for podroll/publisher and ignored for subscribe.
struct PodcastRemoteItem: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String { "\(feedGuid ?? "")|\(feedUrl ?? "")|\(title ?? "")|\(itemGuid ?? "")" }
    /// Required `feedGuid` from the feed when provided. Nil when absent — never invent.
    var feedGuid: String?
    /// Optional remote feed URL from the feed. Nil when absent — never invent.
    var feedUrl: String?
    /// Optional display title hint from the feed. Nil when absent — never invent / never look up.
    var title: String?
    /// Optional `medium` attribute (e.g. podcast, music). Nil when absent — never invent.
    var medium: String?
    /// Optional `itemGuid` (episode pointer). Rare for podroll; stored when present — never invent.
    var itemGuid: String?

    init(
        feedGuid: String? = nil,
        feedUrl: String? = nil,
        title: String? = nil,
        medium: String? = nil,
        itemGuid: String? = nil
    ) {
        self.feedGuid = feedGuid
        self.feedUrl = feedUrl
        self.title = title
        self.medium = medium
        self.itemGuid = itemGuid
    }

    /// Trimmed non-empty feedGuid when the feed set it.
    var displayFeedGuid: String? {
        guard let feedGuid else { return nil }
        let trimmed = feedGuid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty itemGuid when the feed set it. Hidden when missing — never invent.
    var displayItemGuid: String? {
        guard let itemGuid else { return nil }
        let trimmed = itemGuid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty feedUrl string when the feed set it.
    var displayFeedUrl: String? {
        guard let feedUrl else { return nil }
        let trimmed = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty title when the feed set it. Hidden when missing — never invent titles.
    var displayTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty medium when the feed set it.
    var displayMedium: String? {
        guard let medium else { return nil }
        let trimmed = medium.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) URL for the remote feed when `feedUrl` looks like one. Nil otherwise — never invent.
    var openURL: URL? {
        guard let raw = displayFeedUrl else { return nil }
        guard let parsed = URL(string: raw) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// Primary line for UI: title → feedUrl → feedGuid (first non-empty). Nil when none.
    var primaryLabel: String? {
        displayTitle ?? displayFeedUrl ?? displayFeedGuid
    }
}

/// Display helpers for channel `podcast:podroll` / nested `podcast:remoteItem`.
/// Feed-provided only; Open / Copy / optional Subscribe-by-URL preview. Cap 20.
enum PodcastPodrollDisplay {
    /// Soft UI cap — show first N after feed order; honesty footnote when more exist.
    static let displayCap = 20

    /// Entries with feedGuid and/or feedUrl (at least one identifier). Feed order. Never invent.
    static func valid(_ items: [PodcastRemoteItem]) -> [PodcastRemoteItem] {
        items.compactMap { item in
            let guid = item.displayFeedGuid
            let url = item.displayFeedUrl
            guard guid != nil || url != nil else { return nil }
            return PodcastRemoteItem(
                feedGuid: guid,
                feedUrl: url,
                title: item.displayTitle,
                medium: item.displayMedium,
                itemGuid: {
                    guard let g = item.itemGuid else { return nil }
                    let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }()
            )
        }
    }

    /// First `displayCap` + whether the feed listed more valid remote items.
    static func capped(_ items: [PodcastRemoteItem]) -> (shown: [PodcastRemoteItem], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Pasteboard line: optional title + url + guid from the feed only.
    static func copyText(_ item: PodcastRemoteItem) -> String {
        var parts: [String] = []
        if let title = item.displayTitle { parts.append(title) }
        if let url = item.displayFeedUrl { parts.append(url) }
        if let guid = item.displayFeedGuid { parts.append(guid) }
        if let itemGuid = item.displayItemGuid { parts.append(itemGuid) }
        return parts.joined(separator: "\n")
    }
}


/// Display helpers for channel `podcast:publisher` / nested `podcast:remoteItem`.
/// Feed-provided only; Open / Copy / optional Subscribe-by-URL preview. Cap 1 (namespace: usually exactly one).
enum PodcastPublisherDisplay {
    /// Soft UI cap — show first N after feed order; honesty footnote when more exist.
    /// Podcasting 2.0 allows a single nested remoteItem; keep a tiny cap if a feed misbehaves.
    static let displayCap = 1

    /// Entries with feedGuid and/or feedUrl (at least one identifier). Feed order. Never invent.
    static func valid(_ items: [PodcastRemoteItem]) -> [PodcastRemoteItem] {
        PodcastPodrollDisplay.valid(items)
    }

    /// First `displayCap` + whether the feed listed more valid remote items.
    static func capped(_ items: [PodcastRemoteItem]) -> (shown: [PodcastRemoteItem], truncated: Bool) {
        let list = valid(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Pasteboard line: optional title + url + guid from the feed only.
    static func copyText(_ item: PodcastRemoteItem) -> String {
        PodcastPodrollDisplay.copyText(item)
    }
}

/// Podcast Index `podcast:contentLink` — fallback / alternate platform link under `podcast:liveItem` (or item).
/// Element text = label; `href` required. Feed-provided only — never invent URLs.
struct PodcastContentLink: Identifiable, Hashable, Codable {
    var id: String { "\(href)|\(label ?? "")" }
    /// Required `href` URI from the feed.
    var href: String
    /// Optional element text describing the destination (e.g. "YouTube!", "Listen Live!").
    var label: String?

    init(href: String, label: String? = nil) {
        self.href = href
        self.label = label
    }

    /// Trimmed non-empty label when the feed set element text.
    var displayLabel: String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) URL from feed `href` only. Nil when missing / non-http(s).
    var browserURL: URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

/// Podcast Index `podcast:liveItem` status values (required attribute).
enum PodcastLiveItemStatus: String, Hashable, Codable {
    case pending
    case live
    case ended

    /// Parse feed attribute; nil when missing/unknown — never invent.
    static func parse(_ raw: String?) -> PodcastLiveItemStatus? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "pending": return .pending
        case "live": return .live
        case "ended": return .ended
        default: return nil
        }
    }

    /// Sort rank: live first, then pending, then ended.
    var sortRank: Int {
        switch self {
        case .live: return 0
        case .pending: return 1
        case .ended: return 2
        }
    }
}

/// Podcast Index `podcast:liveItem` — channel-level live stream metadata (display-only).
/// Required: `status` + `start`. Recommended: `end`. Children: title, link, guid, contentLink, …
/// **Display-only:** this app does **not** play live enclosures, record, open chat, or process payments.
/// Feed-provided only — never invent live items.
struct PodcastLiveItem: Identifiable, Hashable, Codable {
    /// Stable list identity from feed fields.
    var id: String {
        let links = contentLinks.map(\.id).joined(separator: ";")
        return "\(status.rawValue)|\(start)|\(end ?? "")|\(title ?? "")|\(guid ?? "")|\(link ?? "")|\(links)"
    }
    /// Required status: pending / live / ended.
    var status: PodcastLiveItemStatus
    /// Raw `start` ISO8601 attribute as provided.
    var start: String
    /// Parsed `start` epoch ms when parsable; nil when unparsable — never invent.
    var startEpochMs: Int64?
    /// Raw `end` ISO8601 attribute when provided.
    var end: String?
    /// Parsed `end` epoch ms when parsable.
    var endEpochMs: Int64?
    /// Child `<title>` when provided.
    var title: String?
    /// Child `<link>` / alternate http(s) page when provided.
    var link: String?
    /// Child `<guid>` when provided (identity only — not used as subscription key).
    var guid: String?
    /// Nested `podcast:contentLink` fallback / platform links (feed-provided).
    var contentLinks: [PodcastContentLink]

    init(
        status: PodcastLiveItemStatus,
        start: String,
        startEpochMs: Int64? = nil,
        end: String? = nil,
        endEpochMs: Int64? = nil,
        title: String? = nil,
        link: String? = nil,
        guid: String? = nil,
        contentLinks: [PodcastContentLink] = []
    ) {
        self.status = status
        self.start = start
        self.startEpochMs = startEpochMs
        self.end = end
        self.endEpochMs = endEpochMs
        self.title = title
        self.link = link
        self.guid = guid
        self.contentLinks = contentLinks
    }

    /// Trimmed non-empty title when the feed set it.
    var displayTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) page URL from feed `<link>` only. Nil when missing / non-http(s).
    var linkURL: URL? {
        guard let link else { return nil }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Openable http(s) contentLinks from the feed (label optional).
    var openableContentLinks: [PodcastContentLink] {
        contentLinks.filter { $0.browserURL != nil }
    }
}

/// Display helpers for channel `podcast:liveItem` (feed-provided only; display-only — no live player).
enum PodcastLiveItemDisplay {
    /// Soft UI cap — show first N; honesty footnote when more exist.
    static let displayCap = 20

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Valid live items: known status + non-empty start. Feed order preserved then sorted for UI.
    /// Never invents items / times / links.
    static func valid(_ items: [PodcastLiveItem]) -> [PodcastLiveItem] {
        items.compactMap { item in
            let start = item.start.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !start.isEmpty else { return nil }
            let links = item.contentLinks.compactMap { link -> PodcastContentLink? in
                let href = link.href.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !href.isEmpty else { return nil }
                return PodcastContentLink(href: href, label: link.displayLabel)
            }
            return PodcastLiveItem(
                status: item.status,
                start: start,
                startEpochMs: item.startEpochMs,
                end: {
                    guard let end = item.end?.trimmingCharacters(in: .whitespacesAndNewlines), !end.isEmpty else {
                        return nil
                    }
                    return end
                }(),
                endEpochMs: item.endEpochMs,
                title: item.displayTitle,
                link: {
                    guard let link = item.link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty else {
                        return nil
                    }
                    return link
                }(),
                guid: {
                    guard let guid = item.guid?.trimmingCharacters(in: .whitespacesAndNewlines), !guid.isEmpty else {
                        return nil
                    }
                    return guid
                }(),
                contentLinks: links
            )
        }
    }

    /// Prefer live → pending → ended; within same status newest `start` first (missing dates last).
    static func sorted(_ items: [PodcastLiveItem]) -> [PodcastLiveItem] {
        valid(items).sorted { lhs, rhs in
            if lhs.status.sortRank != rhs.status.sortRank {
                return lhs.status.sortRank < rhs.status.sortRank
            }
            let l = lhs.startEpochMs ?? Int64.min
            let r = rhs.startEpochMs ?? Int64.min
            if l != r { return l > r }
            let lt = lhs.displayTitle ?? ""
            let rt = rhs.displayTitle ?? ""
            return lt.localizedCaseInsensitiveCompare(rt) == .orderedAscending
        }
    }

    /// First `displayCap` sorted items + whether more exist in the feed.
    static func capped(_ items: [PodcastLiveItem]) -> (shown: [PodcastLiveItem], truncated: Bool) {
        let list = sorted(items)
        if list.count <= displayCap {
            return (list, false)
        }
        return (Array(list.prefix(displayCap)), true)
    }

    /// Localized status label for UI / VoiceOver.
    static func statusLabel(_ status: PodcastLiveItemStatus) -> String {
        switch status {
        case .pending: return String(localized: "Pending")
        case .live: return String(localized: "Live")
        case .ended: return String(localized: "Ended")
        }
    }

    /// Format start/end for display: medium date + short time when epoch known; else raw feed string.
    static func formatTimestamp(raw: String, epochMs: Int64?) -> String {
        if let epochMs {
            let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000.0)
            return dateTime.string(from: date)
        }
        return raw
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
    /// Feed-provided Podcast Index transcript language attribute; nil when absent.
    var transcriptLanguage: String?
    /// Chapters: feed PSC/Atom, fetched Podcast Index JSON, or media-file tags (when persisted after local read).
    var chapters: [PodcastChapter]
    /// Podcast Index `podcast:chapters` remote JSON URL (fetched lazily when needed).
    var podcastIndexChapterUrl: String?
    /// Podcast Index `podcast:chapters` MIME `type` attribute when the feed provides it (e.g. application/json).
    /// `nil` when absent — never invent. Display-only caption; fetch still uses `PodcastIndexChapterParser`.
    var podcastIndexChapterType: String?
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
    /// iTunes episode type from `itunes:episodeType` (raw feed string: `full` / `trailer` / `bonus` / …).
    /// `nil` = not in feed — never invent. Display localizes known; unknown → show raw; hide when missing.
    var episodeType: String?
    /// `itunes:explicit` yes/true/explicit on the item (or inherited from channel when item omits it).
    /// `false` when missing, clean/no/false, or unknown — never invent; UI hides badge unless true.
    var isExplicit: Bool
    /// Item-level Podcast Index `podcast:medium` raw string when the feed provides it (e.g. podcast / music / video).
    /// Nil when absent — never invent or remap; UI hides unless present. Display-only — does not change playback.
    var medium: String?
    /// Item-level Podcast Index `podcast:person` entries when the feed provides them.
    /// Empty when absent — never invent people; UI hides when empty.
    var people: [PodcastPerson]
    /// Item-level Podcast Index `podcast:location` entries when the feed provides them.
    /// Empty when absent — never invent locations / never geocode names; UI hides when empty.
    var locations: [PodcastLocation]
    /// Item-level Podcast Index `podcast:socialInteract` entries when the feed provides them.
    /// Empty when absent — never invent discussion URLs or account IDs; UI hides when empty / disabled. openURL / Share / Copy only.
    var socialInteracts: [PodcastSocialInteract]
    /// Item-level Podcast Index `podcast:value` / valueRecipient blocks when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — no Lightning / wallet sends.
    var values: [PodcastValue]
    /// Item-level Podcast Index `podcast:alternateEnclosure` (+ nested `podcast:source`) when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — Open URL / Copy; does **not** switch the player.
    var alternateEnclosures: [PodcastAlternateEnclosure]
    /// Item-level Podcast Index `podcast:soundbite` (startTime + duration; optional title) when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. Play soundbite via PlaybackService (seek + end pause) — **no** separate clip player.
    var soundbites: [PodcastSoundbite]
    /// Item-level Podcast Index `podcast:txt` (optional purpose + text) when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — Copy / Open http(s); no Social / Matrix clients.
    var texts: [PodcastTxt]
    /// Item-level Podcast Index `podcast:license` (text and/or optional url) when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — show text; Open http(s) / Copy; **no DRM**.
    var licenses: [PodcastLicense]
    /// Item-level Podcast Index `podcast:images` / `podcast:image` variants when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. Prefer one higher-res http(s) for artwork; Open/Copy list — do **not** download all eagerly.
    var images: [PodcastImageVariant]

    /// Feed provides a remote transcript URL (no on-device STT).
    var hasTranscriptURL: Bool {
        guard let transcriptUrl, !transcriptUrl.isEmpty else { return false }
        return true
    }

    /// Feed provides a Podcast Index `podcast:chapters` remote URL (Open / Copy + lazy JSON fetch).
    var hasPodcastIndexChapterURL: Bool {
        guard let podcastIndexChapterUrl, !podcastIndexChapterUrl.isEmpty else { return false }
        return true
    }

    /// Trimmed non-empty feed-provided transcript language. Hidden when missing — never invent a language.
    /// The raw feed string is display/copy/share text; no locale or language code is synthesized.
    var displayTranscriptLanguage: String? {
        guard let transcriptLanguage else { return nil }
        let trimmed = transcriptLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty feed-provided transcript type. Hidden when missing — never invent MIME.
    /// The raw `transcriptType` remains the fetch hint; this value is display/copy/share text only.
    var displayTranscriptType: String? {
        guard let transcriptType else { return nil }
        let trimmed = transcriptType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty `podcast:chapters` type attribute. Hidden when missing — never invent MIME.
    var displayPodcastIndexChapterType: String? {
        guard let podcastIndexChapterType else { return nil }
        let trimmed = podcastIndexChapterType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// http(s) chapters URL for Open / Copy when the feed provided one.
    var podcastIndexChapterOpenURL: URL? {
        guard let raw = podcastIndexChapterUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
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
        transcriptLanguage: String? = nil,
        chapters: [PodcastChapter] = [],
        podcastIndexChapterUrl: String? = nil,
        podcastIndexChapterType: String? = nil,
        descriptionText: String? = nil,
        durationSeconds: Double = 0,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeType: String? = nil,
        isExplicit: Bool = false,
        medium: String? = nil,
        people: [PodcastPerson] = [],
        locations: [PodcastLocation] = [],
        socialInteracts: [PodcastSocialInteract] = [],
        values: [PodcastValue] = [],
        alternateEnclosures: [PodcastAlternateEnclosure] = [],
        soundbites: [PodcastSoundbite] = [],
        texts: [PodcastTxt] = [],
        licenses: [PodcastLicense] = [],
        images: [PodcastImageVariant] = []
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
        self.transcriptLanguage = transcriptLanguage
        self.chapters = chapters
        self.podcastIndexChapterUrl = podcastIndexChapterUrl
        self.podcastIndexChapterType = podcastIndexChapterType
        self.descriptionText = descriptionText
        self.durationSeconds = durationSeconds
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeType = episodeType
        self.isExplicit = isExplicit
        self.medium = medium
        self.people = people
        self.locations = locations
        self.socialInteracts = socialInteracts
        self.values = values
        self.alternateEnclosures = alternateEnclosures
        self.soundbites = soundbites
        self.texts = texts
        self.licenses = licenses
        self.images = images
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
        transcriptLanguage = try c.decodeIfPresent(String.self, forKey: .transcriptLanguage)
        chapters = try c.decodeIfPresent([PodcastChapter].self, forKey: .chapters) ?? []
        podcastIndexChapterUrl = try c.decodeIfPresent(String.self, forKey: .podcastIndexChapterUrl)
        podcastIndexChapterType = try c.decodeIfPresent(String.self, forKey: .podcastIndexChapterType)
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber)
        episodeType = try c.decodeIfPresent(String.self, forKey: .episodeType)
        isExplicit = try c.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
        medium = try c.decodeIfPresent(String.self, forKey: .medium)
        people = try c.decodeIfPresent([PodcastPerson].self, forKey: .people) ?? []
        locations = try c.decodeIfPresent([PodcastLocation].self, forKey: .locations) ?? []
        socialInteracts = try c.decodeIfPresent([PodcastSocialInteract].self, forKey: .socialInteracts) ?? []
        values = try c.decodeIfPresent([PodcastValue].self, forKey: .values) ?? []
        alternateEnclosures = try c.decodeIfPresent([PodcastAlternateEnclosure].self, forKey: .alternateEnclosures) ?? []
        soundbites = try c.decodeIfPresent([PodcastSoundbite].self, forKey: .soundbites) ?? []
        texts = try c.decodeIfPresent([PodcastTxt].self, forKey: .texts) ?? []
        licenses = try c.decodeIfPresent([PodcastLicense].self, forKey: .licenses) ?? []
        images = try c.decodeIfPresent([PodcastImageVariant].self, forKey: .images) ?? []
    }

    /// Trimmed non-empty item `podcast:medium` from the feed. Hidden when missing — never invent / never remap.
    var displayMedium: String? {
        guard let medium else { return nil }
        let trimmed = medium.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Non-empty named item-level `podcast:person` entries (hide when empty — never invent).
    var displayPeople: [PodcastPerson] {
        PodcastPeopleDisplay.valid(people)
    }

    /// Non-empty named item-level `podcast:location` entries (hide when empty — never invent / never geocode).
    var displayLocations: [PodcastLocation] {
        PodcastLocationDisplay.valid(locations)
    }

    /// Openable item-level `podcast:socialInteract` entries (hide when empty / disabled — never invent URLs or account IDs).
    var displaySocialInteracts: [PodcastSocialInteract] {
        PodcastSocialInteractDisplay.valid(socialInteracts)
    }

    /// Highest-priority openable item socialInteract (openURL Discuss). Nil when none.
    var preferredSocialInteract: PodcastSocialInteract? {
        PodcastSocialInteractDisplay.preferred(socialInteracts)
    }

    /// Flattened item-level `podcast:value` recipients (hide when empty — never invent; display-only).
    var displayValueRecipients: [PodcastValueRecipientRow] {
        PodcastValueDisplay.valid(values)
    }

    /// Valid item-level `podcast:alternateEnclosure` entries (hide when empty — never invent; http(s) Play + Open + Copy / Share).
    var displayAlternateEnclosures: [PodcastAlternateEnclosure] {
        PodcastAlternateEnclosureDisplay.valid(alternateEnclosures)
    }

    /// Valid item-level `podcast:soundbite` entries (hide when empty — never invent; Play soundbite / Copy).
    var displaySoundbites: [PodcastSoundbite] {
        PodcastSoundbiteDisplay.valid(soundbites)
    }

    /// Valid item-level `podcast:txt` entries (hide when empty — never invent; display-only Copy / Open http(s)).
    var displayTexts: [PodcastTxt] {
        PodcastTxtDisplay.valid(texts)
    }

    /// Valid item-level `podcast:license` entries (hide when empty — never invent; display-only; no DRM).
    var displayLicenses: [PodcastLicense] {
        PodcastLicenseDisplay.valid(licenses)
    }

    /// Valid item-level `podcast:images` / `podcast:image` variants (hide when empty — never invent; Open/Copy/Share; prefer one for artwork).
    var displayImages: [PodcastImageVariant] {
        PodcastImagesDisplay.valid(images)
    }

    /// Preferred item artwork URL from `podcast:images` / `podcast:image` when present (http(s)). Nil → fall back to feed artwork.
    var preferredPodcastImagesArtworkURL: String? {
        PodcastImagesDisplay.preferredArtworkURL(images)
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

    /// Trimmed non-empty `itunes:episodeType` from the feed. Hidden when missing — never invent.
    var episodeTypeCode: String? {
        guard let episodeType else { return nil }
        let trimmed = episodeType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Capsule / row label for `itunes:episodeType`: localized Full / Trailer / Bonus when known; else raw feed string.
    /// `nil` when missing — never invent. List chips (`EpisodeTypeFilter`) may filter on the same parsed field.
    /// Distinct from channel `podcast:trailer` (Feed detail teaser).
    var displayEpisodeType: String? {
        guard let code = episodeTypeCode else { return nil }
        switch code.lowercased() {
        case "full":
            return String(localized: "Full")
        case "trailer":
            return String(localized: "Trailer")
        case "bonus":
            return String(localized: "Bonus")
        default:
            return code
        }
    }

    /// VoiceOver for item `itunes:episodeType` (localized known values; "Episode type …" for unknown raw).
    var episodeTypeAccessibilityLabel: String? {
        guard let code = episodeTypeCode else { return nil }
        switch code.lowercased() {
        case "full":
            return String(localized: "Full")
        case "trailer":
            return String(localized: "Trailer")
        case "bonus":
            return String(localized: "Bonus")
        default:
            return String(localized: "Episode type \(code)")
        }
    }

    /// Alias for `displayEpisodeType` (EpisodeRow / legacy caption call sites).
    var episodeTypeCaption: String? { displayEpisodeType }
}


/// Podcast Index channel `podcast:updateFrequency` (Podcasting 2.0).
/// Free-form display text (node value, typically ≤128 chars) + optional attributes:
/// `rrule` (iCalendar RFC 5545), `dtstart` (ISO8601), `complete` (boolean — no further episodes).
/// **Display-only:** never invent schedule text; does **not** change Keep updated / refresh interval.
/// Feed-provided only — hide when the tag is absent or empty of all fields.
struct PodcastUpdateFrequency: Hashable, Codable {
    /// Element text as provided by the feed (free-form schedule label). Nil/blank when absent.
    var text: String?
    /// Optional `rrule` attribute (raw). Nil when absent — never invent recurrence rules.
    var rrule: String?
    /// Optional `dtstart` attribute (raw ISO8601 date/datetime). Nil when absent — never invent.
    var dtstart: String?
    /// Optional `complete` attribute. `true` = feed claims no further episodes; `nil` when absent (do not assume false for display gating).
    var complete: Bool?

    init(text: String? = nil, rrule: String? = nil, dtstart: String? = nil, complete: Bool? = nil) {
        self.text = text
        self.rrule = rrule
        self.dtstart = dtstart
        self.complete = complete
    }

    /// True when any field has feed-provided content worth showing.
    var hasContent: Bool {
        displayText != nil || displayRrule != nil || displayDtstart != nil || complete == true
    }

    /// Trimmed non-empty free-form text (spec suggests ≤128; we store as provided, UI may truncate display).
    var displayText: String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty raw `rrule`. Hidden when missing — never invent.
    var displayRrule: String? {
        guard let rrule else { return nil }
        let trimmed = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Exact localized Recurrence footnote caption shown in the UI (same string Copy/Share uses).
    /// Nil when `displayRrule` is missing — never invent Daily/Weekly.
    var displayRruleCaption: String? {
        guard let r = displayRrule else { return nil }
        return String(localized: "Recurrence \(r)")
    }

    /// Trimmed non-empty raw `dtstart`. Hidden when missing — never invent.
    var displayDtstart: String? {
        guard let dtstart else { return nil }
        let trimmed = dtstart.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Exact localized Starts footnote caption shown in the UI (same string Copy/Share uses).
    /// Nil when `displayDtstart` is missing — never invent.
    var displayDtstartCaption: String? {
        guard let d = displayDtstart else { return nil }
        return String(localized: "Starts \(d)")
    }

    /// Feed claims no further episodes via `complete="true"`.
    var isComplete: Bool { complete == true }

    /// Capsule / row primary label: free-form text when set; else localized **Complete** when `complete`; else nil
    /// (structured-only rows still show via `hasContent` with footnotes for rrule/dtstart).
    /// Never invents Daily/Weekly from rrule alone.
    var displayLabel: String? {
        if let t = displayText { return t }
        if isComplete { return String(localized: "Complete") }
        return nil
    }

    /// Same human-visible, feed-backed summary used by Copy and Share.
    /// The generic “Update frequency” placeholder is intentionally omitted: it is UI scaffolding, not feed data.
    var shareText: String? {
        var parts: [String] = []
        if let label = displayLabel {
            parts.append(label)
        }
        if isComplete {
            parts.append(String(localized: "This podcast claims it will not release further episodes. This does not change Keep updated or refresh."))
        }
        if let r = displayRruleCaption {
            parts.append(r)
        }
        if let d = displayDtstartCaption {
            parts.append(d)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    /// VoiceOver summary for the update-frequency block.
    var accessibilityLabel: String {
        var parts: [String] = []
        if let t = displayText {
            parts.append(String(localized: "Update frequency \(t)"))
        } else if isComplete {
            parts.append(String(localized: "Complete"))
        } else {
            parts.append(String(localized: "Update frequency"))
        }
        if isComplete {
            parts.append(String(localized: "This podcast claims it will not release further episodes. This does not change Keep updated or refresh."))
        }
        if let r = displayRruleCaption {
            parts.append(r)
        }
        if let d = displayDtstartCaption {
            parts.append(d)
        }
        return parts.joined(separator: ". ")
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
    /// Channel Podcast Index `podcast:medium` raw string when the feed provides it (e.g. podcast / music / video / audiobook).
    /// Nil when absent — never invent or remap beyond display; UI hides unless present. Display-only — does not change playback.
    var medium: String?
    /// Channel `itunes:type` raw string when the feed provides it (Apple Podcasts: `episodic` / `serial`).
    /// Nil when absent — never invent; UI hides unless present. Unknown values kept as raw for display.
    /// Capsule is display-only. Separate one-shot heuristic may set per-feed `episodeSort` to Oldest first
    /// when canonical type is `serial` and `episodeSort` is still nil (never invent type; never override user sort).
    var itunesType: String?
    /// Channel Podcast Index `podcast:updateFrequency` when the feed provides it (text + optional rrule/dtstart/complete).
    /// Nil when absent — never invent schedule; UI hides unless present. Display-only — does **not** change Keep updated / refresh.
    var updateFrequency: PodcastUpdateFrequency?
    /// Channel Apple Podcasts `itunes:complete` yes/true. `false` when missing/no — never invent; UI hides unless true.
    /// Display-only — does **not** change Keep updated / refresh. **Distinct** from `podcast:updateFrequency` `complete` (both may show).
    var isItunesComplete: Bool
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
    /// Channel `podcast:block` and/or `itunes:block` yes/true (OR across tags). `false` when absent/no — never invent; UI hides unless true.
    /// Display-only directory metadata — this app does **not** enforce (subscribe/play still allowed). **Distinct** from `podcast:locked`.
    var isBlocked: Bool
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
    /// Channel-level Podcast Index `podcast:location` entries when the feed provides them.
    /// Empty when absent — never invent locations / never geocode names; UI hides when empty.
    var locations: [PodcastLocation]
    /// Channel-level Podcast Index `podcast:socialInteract` entries when the feed provides them.
    /// Empty when absent — never invent discussion URLs or account IDs; UI hides when empty / disabled. openURL / Share / Copy only.
    var socialInteracts: [PodcastSocialInteract]
    /// Channel-level Podcast Index `podcast:value` / valueRecipient blocks when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — no Lightning / wallet sends.
    var values: [PodcastValue]
    /// Channel-level Podcast Index `podcast:liveItem` entries when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — no live stream player / recording / chat.
    var liveItems: [PodcastLiveItem]
    /// Channel-level Podcast Index `podcast:txt` (optional purpose + text) when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — Copy / Open http(s); no Social / Matrix clients.
    var texts: [PodcastTxt]
    /// Channel-level Podcast Index `podcast:license` (text and/or optional url) when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. **Display-only** — show text; Open http(s) / Copy; **no DRM**.
    var licenses: [PodcastLicense]
    /// Channel-level Podcast Index `podcast:images` / `podcast:image` variants when the feed provides them.
    /// Empty when absent — never invent; UI hides when empty. Prefer one higher-res http(s) for Feed detail / Full player / Now Playing; Open/Copy list — do **not** download all eagerly.
    var images: [PodcastImageVariant]
    /// Channel-level Podcast Index `podcast:podroll` / nested `podcast:remoteItem` when the feed provides them.
    /// Empty when absent — never invent recommendations; UI hides when empty. **Display-only** — Open / Copy / Subscribe-by-URL preview.
    var podrollItems: [PodcastRemoteItem]
    /// Channel-level Podcast Index `podcast:publisher` / nested `podcast:remoteItem` when the feed provides them.
    /// Empty when absent — never invent publishers; UI hides when empty. **Display-only** — Open / Copy / Subscribe-by-URL preview.
    /// Namespace typically has exactly one remoteItem pointing at the publisher feed.
    var publisherItems: [PodcastRemoteItem]
    var episodes: [PodcastEpisode]
    /// Epoch ms of the last **successful** network feed refresh/parse for this subscription.
    /// `nil` when never successfully refreshed (legacy JSON) or for local-folder feeds (no network refresh — hide UI; do not invent).
    /// Updated only on successful `subscribeQuietly` / fetch+parse; failed refresh leaves the previous value.
    /// Local JSON / backup only — not OPML. Removed with the feed on unsubscribe.
    var lastRefreshedAtEpochMs: Int64?

    /// Non-empty feed description (may still contain HTML).
    var hasDescriptionText: Bool {
        guard let descriptionText else { return false }
        return !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// User-facing podcast name: `FeedSettings.customTitle` when set, else RSS/`title`.
    /// Does not mutate this feed object — nickname lives only in feed settings.
    func displayTitle(settings: FeedSettings) -> String {
        if let custom = settings.customTitle, !custom.isEmpty {
            return custom
        }
        return title
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

    /// Trimmed non-empty channel `podcast:medium` from the feed. Hidden when missing — never invent / never remap.
    var displayMedium: String? {
        guard let medium else { return nil }
        let trimmed = medium.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed non-empty channel `itunes:type` from the feed. Hidden when missing — never invent.
    var itunesTypeCode: String? {
        guard let itunesType else { return nil }
        let trimmed = itunesType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `true` only when the feed’s parsed channel `itunes:type` canonicalizes to `serial` (never invent).
    var isItunesTypeSerial: Bool {
        guard let itunesType else { return false }
        return ItunesTypeParsing.canonical(from: itunesType) == "serial"
    }

    /// Capsule / row label for `itunes:type`: localized Episodic/Serial when known; else raw feed string.
    /// `nil` when missing — never invent. Capsule is display-only (sort uses a separate nil-only Serial heuristic).
    var displayItunesType: String? {
        guard let code = itunesTypeCode else { return nil }
        switch code.lowercased() {
        case "episodic":
            return String(localized: "Episodic")
        case "serial":
            return String(localized: "Serial")
        default:
            return code
        }
    }

    /// VoiceOver for channel `itunes:type` (localized known values; "Podcast type …" for unknown raw).
    var itunesTypeAccessibilityLabel: String? {
        guard let code = itunesTypeCode else { return nil }
        switch code.lowercased() {
        case "episodic":
            return String(localized: "Episodic")
        case "serial":
            return String(localized: "Serial")
        default:
            return String(localized: "Podcast type \(code)")
        }
    }

    /// Channel `podcast:updateFrequency` when the feed provided any displayable field. Nil when absent — never invent.
    var displayUpdateFrequency: PodcastUpdateFrequency? {
        guard let updateFrequency, updateFrequency.hasContent else { return nil }
        return updateFrequency
    }

    /// VoiceOver for channel `itunes:complete=yes` badge + honest display-only footnote.
    /// Distinct from `podcast:updateFrequency` complete VoiceOver (both may appear).
    var itunesCompleteShareText: String {
        [
            String(localized: "Complete"),
            String(localized: "This podcast marks itunes:complete. The publisher claims no further episodes. This does not change Keep updated or refresh.")
        ].joined(separator: ". ")
    }

    /// VoiceOver for channel `itunes:complete=yes` badge + honest display-only footnote.
    /// Distinct from `podcast:updateFrequency` complete VoiceOver (both may appear).
    var itunesCompleteAccessibilityLabel: String {
        itunesCompleteShareText
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

    /// VoiceOver for channel podcast:block / itunes:block yes badge + honest display-only footnote.
    /// Distinct from podcast:locked VoiceOver (both may appear).
    var podcastBlockAccessibilityLabel: String {
        [
            String(localized: "Blocked"),
            String(localized: "This feed marks podcast:block or itunes:block for directories. This app does not enforce it — subscribe and play still work.")
        ].joined(separator: ". ")
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

    /// Non-empty named channel-level `podcast:location` entries (hide when empty — never invent / never geocode).
    var displayLocations: [PodcastLocation] {
        PodcastLocationDisplay.valid(locations)
    }

    /// Openable channel-level `podcast:socialInteract` entries (hide when empty / disabled — never invent URLs or account IDs).
    var displaySocialInteracts: [PodcastSocialInteract] {
        PodcastSocialInteractDisplay.valid(socialInteracts)
    }

    /// Highest-priority openable channel socialInteract (openURL Discuss). Nil when none.
    var preferredSocialInteract: PodcastSocialInteract? {
        PodcastSocialInteractDisplay.preferred(socialInteracts)
    }

    /// Flattened channel-level `podcast:value` recipients (hide when empty — never invent; display-only).
    var displayValueRecipients: [PodcastValueRecipientRow] {
        PodcastValueDisplay.valid(values)
    }

    /// Channel-level `podcast:liveItem` entries (hide when empty — never invent; display-only — no live player).
    var displayLiveItems: [PodcastLiveItem] {
        PodcastLiveItemDisplay.valid(liveItems)
    }

    /// Valid channel-level `podcast:txt` entries (hide when empty — never invent; display-only Copy / Open http(s)).
    var displayTexts: [PodcastTxt] {
        PodcastTxtDisplay.valid(texts)
    }

    /// Valid channel-level `podcast:license` entries (hide when empty — never invent; display-only; no DRM).
    var displayLicenses: [PodcastLicense] {
        PodcastLicenseDisplay.valid(licenses)
    }

    /// Valid channel-level `podcast:images` / `podcast:image` variants (hide when empty — never invent; Open/Copy/Share; prefer one for artwork).
    var displayImages: [PodcastImageVariant] {
        PodcastImagesDisplay.valid(images)
    }

    /// Preferred channel artwork: one higher-res http(s) from `podcast:images`/`podcast:image` when present; else existing `imageUrl` (itunes/RSS/Atom).
    var preferredDisplayArtworkURL: String? {
        if let fromImages = PodcastImagesDisplay.preferredArtworkURL(images) {
            return fromImages
        }
        guard let imageUrl else { return nil }
        let trimmed = imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = URL(string: trimmed) else { return trimmed }
        let scheme = parsed.scheme?.lowercased()
        if scheme == nil || scheme == "http" || scheme == "https" || scheme == "file" {
            return trimmed
        }
        return nil
    }


    /// Date of last successful network refresh when `lastRefreshedAtEpochMs` is set. Hidden when nil / local-folder.
    var lastRefreshedAt: Date? {
        guard let ms = lastRefreshedAtEpochMs else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    /// Channel-level `podcast:podroll` remote items (hide when empty — never invent recommendations; display-only).
    var displayPodrollItems: [PodcastRemoteItem] {
        PodcastPodrollDisplay.valid(podrollItems)
    }

    /// Channel-level `podcast:publisher` remote items (hide when empty — never invent publishers; display-only).
    var displayPublisherItems: [PodcastRemoteItem] {
        PodcastPublisherDisplay.valid(publisherItems)
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
        medium: String? = nil,
        itunesType: String? = nil,
        updateFrequency: PodcastUpdateFrequency? = nil,
        isItunesComplete: Bool = false,
        fundingUrl: String? = nil,
        fundingLabel: String? = nil,
        categories: [String] = [],
        isLocked: Bool = false,
        lockedOwner: String? = nil,
        isBlocked: Bool = false,
        podcastGuid: String? = nil,
        people: [PodcastPerson] = [],
        trailers: [PodcastTrailer] = [],
        locations: [PodcastLocation] = [],
        socialInteracts: [PodcastSocialInteract] = [],
        values: [PodcastValue] = [],
        liveItems: [PodcastLiveItem] = [],
        texts: [PodcastTxt] = [],
        licenses: [PodcastLicense] = [],
        images: [PodcastImageVariant] = [],
        podrollItems: [PodcastRemoteItem] = [],
        publisherItems: [PodcastRemoteItem] = [],
        episodes: [PodcastEpisode],
        lastRefreshedAtEpochMs: Int64? = nil
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
        self.medium = medium
        self.itunesType = itunesType
        self.updateFrequency = updateFrequency
        self.isItunesComplete = isItunesComplete
        self.fundingUrl = fundingUrl
        self.fundingLabel = fundingLabel
        self.categories = categories
        self.isLocked = isLocked
        self.lockedOwner = lockedOwner
        self.isBlocked = isBlocked
        self.podcastGuid = podcastGuid
        self.people = people
        self.trailers = trailers
        self.locations = locations
        self.socialInteracts = socialInteracts
        self.values = values
        self.liveItems = liveItems
        self.texts = texts
        self.licenses = licenses
        self.images = images
        self.podrollItems = podrollItems
        self.publisherItems = publisherItems
        self.episodes = episodes
        self.lastRefreshedAtEpochMs = lastRefreshedAtEpochMs
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
        medium = try c.decodeIfPresent(String.self, forKey: .medium)
        itunesType = try c.decodeIfPresent(String.self, forKey: .itunesType)
        updateFrequency = try c.decodeIfPresent(PodcastUpdateFrequency.self, forKey: .updateFrequency)
        isItunesComplete = try c.decodeIfPresent(Bool.self, forKey: .isItunesComplete) ?? false
        fundingUrl = try c.decodeIfPresent(String.self, forKey: .fundingUrl)
        fundingLabel = try c.decodeIfPresent(String.self, forKey: .fundingLabel)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        lockedOwner = try c.decodeIfPresent(String.self, forKey: .lockedOwner)
        isBlocked = try c.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? false
        podcastGuid = try c.decodeIfPresent(String.self, forKey: .podcastGuid)
        people = try c.decodeIfPresent([PodcastPerson].self, forKey: .people) ?? []
        trailers = try c.decodeIfPresent([PodcastTrailer].self, forKey: .trailers) ?? []
        locations = try c.decodeIfPresent([PodcastLocation].self, forKey: .locations) ?? []
        socialInteracts = try c.decodeIfPresent([PodcastSocialInteract].self, forKey: .socialInteracts) ?? []
        values = try c.decodeIfPresent([PodcastValue].self, forKey: .values) ?? []
        liveItems = try c.decodeIfPresent([PodcastLiveItem].self, forKey: .liveItems) ?? []
        texts = try c.decodeIfPresent([PodcastTxt].self, forKey: .texts) ?? []
        licenses = try c.decodeIfPresent([PodcastLicense].self, forKey: .licenses) ?? []
        images = try c.decodeIfPresent([PodcastImageVariant].self, forKey: .images) ?? []
        podrollItems = try c.decodeIfPresent([PodcastRemoteItem].self, forKey: .podrollItems) ?? []
        publisherItems = try c.decodeIfPresent([PodcastRemoteItem].self, forKey: .publisherItems) ?? []
        episodes = try c.decodeIfPresent([PodcastEpisode].self, forKey: .episodes) ?? []
        lastRefreshedAtEpochMs = try c.decodeIfPresent(Int64.self, forKey: .lastRefreshedAtEpochMs)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, feedUrl, siteLink, imageUrl, descriptionText, author, isExplicit, language, medium, itunesType, updateFrequency, isItunesComplete, fundingUrl, fundingLabel, categories, isLocked, lockedOwner, isBlocked, podcastGuid, people, trailers, locations, socialInteracts, values, liveItems, texts, licenses, images, podrollItems, publisherItems, episodes, lastRefreshedAtEpochMs
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
    /// when to show remaining (typically only for the active chapter). Pure media-timeline
    /// math — UI may speed-adjust via `EpisodeRemainingTime.playerChromeRemainingSeconds`.
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
/// Wall-clock listening estimate from saved playback (not speed-adjusted).
/// Played → `durationSeconds` when known (else 0); in-progress → `positionSeconds` when > 1.
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
