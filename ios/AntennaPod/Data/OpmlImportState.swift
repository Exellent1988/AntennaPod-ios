import Foundation

struct OpmlImportFailure: Identifiable, Hashable {
    var id: String { url + "|" + error }
    let title: String
    let url: String
    let error: String
}

/// Progress for batch OPML subscribe.
struct OpmlImportState: Equatable {
    var total: Int = 0
    var completed: Int = 0
    var succeeded: Int = 0
    var skipped: Int = 0
    var failures: [OpmlImportFailure] = []
    var isImporting: Bool = false
    var currentTitle: String?
    var sourceFileName: String?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var summary: String {
        var parts: [String] = []
        if succeeded > 0 { parts.append(String(localized: "\(succeeded) added")) }
        if skipped > 0 { parts.append(String(localized: "\(skipped) already subscribed")) }
        if !failures.isEmpty { parts.append(String(localized: "\(failures.count) failed")) }
        if parts.isEmpty { return String(localized: "No feeds found") }
        return parts.joined(separator: ", ")
    }
}
