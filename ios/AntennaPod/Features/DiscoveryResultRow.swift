import SwiftUI

/// Shared discovery row (Apple Search, Podcast Index, fyyd, Top lists).
/// Selecting the row or Preview / Open opens the online feed preview (not fire-and-forget subscribe).
struct DiscoveryResultRow: View {
    let title: String
    let author: String
    let artworkURL: URL?
    let feedUrl: String
    let isSubscribed: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(isSubscribed ? String(localized: "Open") : String(localized: "Preview"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(feedUrl.isEmpty)
        .accessibilityLabel(discoveryAccessibilityLabel)
        .accessibilityHint(
            isSubscribed
                ? String(localized: "Opens the subscribed feed")
                : String(localized: "Opens an online feed preview before you confirm subscribe")
        )
    }

    private var discoveryAccessibilityLabel: String {
        let action = isSubscribed
            ? String(localized: "Open subscribed podcast")
            : String(localized: "Preview podcast before subscribe")
        if author.isEmpty {
            return "\(action). \(title)"
        }
        return "\(action). \(title), \(author)"
    }

    @ViewBuilder
    private var artwork: some View {

        let size: CGFloat = 56
        if let url = artworkURL {
            AppAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder
                .frame(width: size, height: size)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
    }
}
