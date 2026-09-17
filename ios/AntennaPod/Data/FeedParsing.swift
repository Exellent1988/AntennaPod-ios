import Foundation

enum FeedParsingError: Error, LocalizedError {
    case emptyResponse
    case unsupported
    case message(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Feed was empty"
        case .unsupported:
            return "Unsupported feed format"
        case .message(let text):
            return text
        }
    }
}

enum FeedParsing {
    static func parse(xml: String) throws -> PodcastFeed {
        try NativeRssAtomParser.parse(xml: xml)
    }
}
