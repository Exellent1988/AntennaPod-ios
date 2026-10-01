import SwiftUI

/// Simple feed-provided `podcast:person` list: name + role when set; tappable http(s) href → system browser.
/// Caps at `PodcastPeopleDisplay.displayCap` with an honesty footnote when truncated.
/// No remote avatar fetch in v1 (img URL stored but not loaded).
struct PodcastPeopleListView: View {
    @Environment(\.openURL) private var openURL

    let people: [PodcastPerson]
    /// Section title (localized by caller).
    var title: String = String(localized: "People")

    private var capped: (shown: [PodcastPerson], truncated: Bool) {
        PodcastPeopleDisplay.capped(people)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, person in
                    personRow(person)
                }

                if result.truncated {
                    Text(String(localized: "Showing first 20 people from the feed."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Showing first 20 people from the feed."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func personRow(_ person: PodcastPerson) -> some View {
        let name = person.displayName ?? person.name
        let role = person.displayRole
        let label: String = {
            if let role {
                return String(localized: "Person \(name), role \(role)")
            }
            return name
        }()

        if let url = person.profileURL {
            Button {
                openURL(url)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let role {
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(String(localized: "Opens this person’s link in the system browser"))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.subheadline)
                if let role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }
}
