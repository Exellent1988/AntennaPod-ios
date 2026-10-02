import SwiftUI
import UIKit

/// Simple feed-provided `podcast:person` list: name + role when set; http(s) href → Open, and any non-blank href → Copy / Share.
/// Caps at `PodcastPeopleDisplay.displayCap` with an honesty footnote when truncated.
/// No remote avatar fetch in v1 (img URL stored but not loaded).
struct PodcastPeopleListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0

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
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Person link copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
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

        let url = person.profileURL
        let copyText = person.href?.trimmingCharacters(in: .whitespacesAndNewlines)
            .flatMap { $0.isEmpty ? nil : $0 }

        VStack(alignment: .leading, spacing: 4) {
            if let url {
                Button {
                    openURL(url)
                } label: {
                    personLabel(name: name, role: role, showsOpenIcon: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint(String(localized: "Opens this person’s link in the system browser"))
            } else {
                personLabel(name: name, role: role, showsOpenIcon: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
            }

            if let copyText {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = copyText
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy person link"))
                    .accessibilityHint(
                        String(localized: "Copies this person’s feed-provided link to the pasteboard")
                    )

                    Group {
                        if let url {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: copyText) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share person link"))
                    .accessibilityHint(
                        String(
                            localized: "Shares this person’s http(s) URL when parseable; otherwise shares the same feed-provided link text as Copy"
                        )
                    )
                }
            }
        }
    }

    private func personLabel(name: String, role: String?, showsOpenIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)
            if let role {
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsOpenIcon {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
