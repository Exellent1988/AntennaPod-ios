import SwiftUI

/// Subscriptions View options, modelled on Android's subscriptions menu:
/// app/src/main/res/menu/subscriptions.xml (subscription_display_list, subscription_num_columns,
/// subscriptions_counter) and ui/screen/subscriptions/SubscriptionFragment.java.
enum SubscriptionsDisplayMode: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: return String(localized: "List")
        case .grid: return String(localized: "Grid")
        }
    }
}

/// Android UserPreferences.PREF_DRAWER_FEED_COUNTER (none / unplayed / downloaded). Default
/// unplayed matches the badge iOS has always shown.
enum SubscriptionsCounterMode: String, CaseIterable, Identifiable {
    case none, unplayed, downloaded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return String(localized: "No counter")
        case .unplayed: return String(localized: "Unplayed episodes")
        case .downloaded: return String(localized: "Downloaded episodes")
        }
    }
}

enum SubscriptionsDisplayKeys {
    static let mode = "subscriptions.displayMode"
    static let columns = "subscriptions.gridColumns"
    static let counter = "subscriptions.counterMode"
}

/// Grid cell: cover art, title, counter badge (Android SubscriptionViewHolder grid layout).
struct SubscriptionGridCell: View {
    let feed: PodcastFeed
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                artwork
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.accentColor, in: Capsule())
                        .padding(4)
                }
            }
            Text(title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        if let raw = feed.imageUrl, let url = URL(string: raw) {
            AppAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: LocalFolderFeed.isLocalFolderFeed(feed) ? "folder.fill" : "mic")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
