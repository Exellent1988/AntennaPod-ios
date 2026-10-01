import SwiftUI

/// Shared discovery row (Apple Search, Podcast Index, Top lists).
struct DiscoveryResultRow: View {
    let title: String
    let author: String
    let artworkURL: URL?
    let feedUrl: String
    let isSubscribed: Bool
    let isSubscribing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSubscribed {
                Text("Subscribed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(isSubscribing ? "…" : "Subscribe") {
                    onSubscribe()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSubscribing || feedUrl.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 56
        if let url = artworkURL {
            AsyncImage(url: url) { phase in
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

