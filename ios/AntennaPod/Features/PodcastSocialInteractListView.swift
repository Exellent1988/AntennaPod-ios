import SwiftUI

/// Simple feed-provided `podcast:socialInteract` list: Discuss opens http(s) URI in the system browser.
/// Priority-sorted (lower = higher); caps at `PodcastSocialInteractDisplay.displayCap` with honesty footnote.
/// **openURL only** — no in-app Fediverse client, no posting / API. Hidden when none / disabled-only.
struct PodcastSocialInteractListView: View {
    @Environment(\.openURL) private var openURL

    let socialInteracts: [PodcastSocialInteract]
    /// Section title (localized by caller).
    var title: String = String(localized: "Discuss")

    private var capped: (shown: [PodcastSocialInteract], truncated: Bool) {
        PodcastSocialInteractDisplay.capped(socialInteracts)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, interact in
                    socialRow(interact)
                }

                if result.truncated {
                    Text(String(localized: "Showing first 20 discussion links from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Showing first 20 discussion links from the feed."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func socialRow(_ interact: PodcastSocialInteract) -> some View {
        let proto = interact.displayProtocol ?? interact.protocolName
        let account = interact.displayAccountId
        let url = interact.discussionURL

        let a11yLabel: String = {
            var parts = [String(localized: "Discuss")]
            parts.append(String(localized: "Protocol \(proto)"))
            if let account { parts.append(String(localized: "Account \(account)")) }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(proto)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let account {
                    Text(account)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)

            if let url {
                Button {
                    openURL(url)
                } label: {
                    Label("Discuss", systemImage: "safari")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Discuss"))
                .accessibilityHint(String(localized: "Opens the discussion link from the feed in the system browser"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
