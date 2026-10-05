import Foundation

extension String {
    /// In-app (local) search match: ignores case and accents, so "muller" finds "Müller" and
    /// "cafe" finds "café". Same locale and empty-query behavior as
    /// `localizedCaseInsensitiveContains` (an empty query matches nothing; callers treat an
    /// empty query as "show all" before calling). Not used for remote iTunes / Podcast Index search.
    func localizedSearchContains(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
    }
}
