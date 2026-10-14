import Foundation

/// One feed outline from an OPML document (AntennaPod-compatible).
struct OpmlOutline: Identifiable, Hashable {
    var id: String { xmlUrl }
    var text: String
    var xmlUrl: String
    var htmlUrl: String?
    var type: String?
}
