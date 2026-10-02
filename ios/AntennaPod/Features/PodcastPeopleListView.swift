import SwiftUI
import UIKit

/// Simple feed-provided `podcast:person` list: name + role/group when set; http(s) href → Open, and any non-blank href → Copy / Share.
/// When `role` is displayed, distinct Copy / Share person role uses that exact text (separate from name+role details and person group).
/// When `group` is displayed, distinct Copy / Share person group uses that exact text (separate from name+role details).
/// Caps at `PodcastPeopleDisplay.displayCap` with an honesty footnote when truncated.
/// No remote avatar fetch in v1 (img URL stored but not loaded).
struct PodcastPeopleListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Person link copied to the pasteboard.")
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
                Text(copiedMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func personRow(_ person: PodcastPerson) -> some View {
        let name = person.displayName ?? person.name
        let role = person.displayRole
        let groupText = person.displayGroup
        let label: String = {
            switch (role, groupText) {
            case let (role?, group?):
                return String(localized: "Person \(name), role \(role), group \(group)")
            case let (role?, nil):
                return String(localized: "Person \(name), role \(role)")
            case let (nil, group?):
                return String(localized: "Person \(name), group \(group)")
            case (nil, nil):
                return name
            }
        }()

        let url = person.profileURL
        let detailsText = [name, role].compactMap { $0 }.joined(separator: " · ")
        let copyText = person.href?.trimmingCharacters(in: .whitespacesAndNewlines)
            .flatMap { $0.isEmpty ? nil : $0 }

        VStack(alignment: .leading, spacing: 4) {
            if let url {
                Button {
                    openURL(url)
                } label: {
                    personLabel(name: name, role: role, group: groupText, showsOpenIcon: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint(String(localized: "Opens this person’s link in the system browser"))
            } else {
                personLabel(name: name, role: role, group: groupText, showsOpenIcon: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = detailsText
                    copiedMessage = String(localized: "Person details copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy person details", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy person details"))
                .accessibilityHint(
                    String(
                        localized: "Copies the displayed person name and role as plain text; role is included only when provided by the feed"
                    )
                )

                ShareLink(item: detailsText) {
                    Label("Share person details", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share person details"))
                .accessibilityHint(
                    String(
                        localized: "Shares the displayed person name and role as plain text; role is included only when provided by the feed"
                    )
                )
            }

            if let role {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = role
                        copiedMessage = String(localized: "Person role copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy person role", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy person role"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed feed-provided person role as plain text")
                    )

                    ShareLink(item: role) {
                        Label("Share person role", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share person role"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed feed-provided person role as plain text")
                    )
                }
            }

            if let groupText {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = groupText
                        copiedMessage = String(localized: "Person group copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy person group", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy person group"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed feed-provided person group as plain text")
                    )

                    ShareLink(item: groupText) {
                        Label("Share person group", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share person group"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed feed-provided person group as plain text")
                    )
                }
            }

            if let copyText {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = copyText
                        copiedMessage = String(localized: "Person link copied to the pasteboard.")
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

    private func personLabel(name: String, role: String?, group: String?, showsOpenIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)
            if let role {
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let group {
                Text(group)
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
