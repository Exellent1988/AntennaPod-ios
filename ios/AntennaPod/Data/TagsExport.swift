import Foundation

enum TagsExport {
    static func plainText(
        tags: [String],
        podcastCountFor: (String) -> Int
    ) -> String {
        let ordered = sortedForExport(tags)
        guard !ordered.isEmpty else { return "" }
        return ordered.enumerated().map { index, tag in
            line(index: index + 1, tag: tag, podcastCount: podcastCountFor(tag))
        }.joined(separator: "\n")
    }

    static func shareText(
        tags: [String],
        podcastCountFor: (String) -> Int
    ) -> String {
        let body = plainText(tags: tags, podcastCountFor: podcastCountFor)
        guard !body.isEmpty else { return "" }
        let header = String(localized: "Tags")
        return "\(header)\n\n\(body)"
    }

    static func sortedForExport(_ tags: [String]) -> [String] {
        tags.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.trimmingCharacters(in: .whitespacesAndNewlines)
                let right = rhs.element.trimmingCharacters(in: .whitespacesAndNewlines)
                switch (left.isEmpty, right.isEmpty) {
                case (false, true):
                    return true
                case (true, false):
                    return false
                case (true, true), (false, false):
                    let comparison = left.localizedCaseInsensitiveCompare(right)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func line(index: Int, tag: String, podcastCount: Int) -> String {
        let displayTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let countLabel: String
        if podcastCount == 1 {
            countLabel = String(localized: "1 podcast")
        } else {
            countLabel = String(format: String(localized: "%lld podcasts"), podcastCount)
        }
        return "\(index). \(displayTag) — \(countLabel)"
    }
}
