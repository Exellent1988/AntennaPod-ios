import Foundation

/// Plain-text export of local feed and episode private notes.
/// Notes remain local until the user explicitly copies or shares this text.
struct PrivateNoteExportItem: Identifiable {
    enum Kind {
        case feed
        case episode
    }

    let kind: Kind
    let feedTitle: String
    let episodeTitle: String?
    let note: String
    let sourceId: String

    var id: String { "\(kind)-\(sourceId)" }

    var displayFeedTitle: String {
        let value = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? String(localized: "Podcast") : value
    }

    var displayEpisodeTitle: String {
        let value = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? String(localized: "Episode") : value
    }
}

enum PrivateNotesExport {
    /// Builds a catalog from every non-empty persisted feed and episode note.
    /// Missing episode/feed metadata is retained with honest fallback labels.
    static func items(
        feeds: [PodcastFeed],
        feedSettingsById: [UUID: FeedSettings],
        episodeNotesById: [String: String]
    ) -> [PrivateNoteExportItem] {
        var result: [PrivateNoteExportItem] = []
        var episodeContext: [String: (feedTitle: String, episodeTitle: String)] = [:]
        var knownFeedIds: Set<UUID> = []

        for feed in feeds {
            knownFeedIds.insert(feed.id)
            let feedTitle = feed.displayTitle(settings: feedSettingsById[feed.id] ?? .default)
            if let note = normalized(feedSettingsById[feed.id]?.privateNote) {
                result.append(
                    PrivateNoteExportItem(
                        kind: .feed,
                        feedTitle: feedTitle,
                        episodeTitle: nil,
                        note: note,
                        sourceId: feed.id.uuidString
                    )
                )
            }
            for episode in feed.episodes {
                episodeContext[episode.id] = (feedTitle, episode.title)
            }
        }

        // Keep any stale settings entry in the export too; metadata may be missing after an
        // interrupted import, but silently dropping a non-empty local note would be worse.
        for (feedId, settings) in feedSettingsById where !knownFeedIds.contains(feedId) {
            guard let note = normalized(settings.privateNote) else { continue }
            result.append(
                PrivateNoteExportItem(
                    kind: .feed,
                    feedTitle: "",
                    episodeTitle: nil,
                    note: note,
                    sourceId: feedId.uuidString
                )
            )
        }

        for (episodeId, rawNote) in episodeNotesById {
            guard let note = normalized(rawNote) else { continue }
            let context = episodeContext[episodeId]
            result.append(
                PrivateNoteExportItem(
                    kind: .episode,
                    feedTitle: context?.feedTitle ?? "",
                    episodeTitle: context?.episodeTitle,
                    note: note,
                    sourceId: episodeId
                )
            )
        }

        return result.sorted { lhs, rhs in
            let lhsFeed = lhs.displayFeedTitle.localizedLowercase
            let rhsFeed = rhs.displayFeedTitle.localizedLowercase
            if lhsFeed != rhsFeed { return lhsFeed < rhsFeed }
            switch (lhs.kind, rhs.kind) {
            case (.feed, .episode): return true
            case (.episode, .feed): return false
            case (.feed, .feed): return lhs.sourceId < rhs.sourceId
            case (.episode, .episode):
                let lhsEpisode = lhs.displayEpisodeTitle.localizedLowercase
                let rhsEpisode = rhs.displayEpisodeTitle.localizedLowercase
                if lhsEpisode != rhsEpisode { return lhsEpisode < rhsEpisode }
                return lhs.sourceId < rhs.sourceId
            }
        }
    }

    /// Plain-text body. Empty when there are no non-empty notes.
    static func plainText(items: [PrivateNoteExportItem]) -> String {
        guard !items.isEmpty else { return "" }
        return items.enumerated().map { index, item in
            switch item.kind {
            case .feed:
                return "\(index + 1). \(String(localized: "Feed")): \(item.displayFeedTitle)\n   \(item.note)"
            case .episode:
                return "\(index + 1). \(String(localized: "Episode")): \(item.displayEpisodeTitle)\n   \(String(localized: "Podcast")): \(item.displayFeedTitle)\n   \(item.note)"
            }
        }.joined(separator: "\n\n")
    }

    /// Plain-text payload for ShareLink, with a localized header.
    static func shareText(items: [PrivateNoteExportItem]) -> String {
        let body = plainText(items: items)
        guard !body.isEmpty else { return "" }
        return "\(String(localized: "Private notes"))\n\n\(body)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
