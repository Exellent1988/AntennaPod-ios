import PodcastCore
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
    // Android FeedCounter order (pref_nav_drawer_feed_counter values): new, unplayed, downloaded,
    // downloaded unplayed, none. Raw values of the original three stay unchanged for saved prefs/backups.
    case new, unplayed, downloaded, downloadedUnplayed, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return String(localized: "No counter")
        case .new: return String(localized: "New episodes")
        case .unplayed: return String(localized: "Unplayed episodes")
        case .downloaded: return String(localized: "Downloaded episodes")
        case .downloadedUnplayed: return String(localized: "Downloaded unplayed episodes")
        }
    }

    /// Rules shared with PodcastCore (Android PodDBAdapter.getFeedCounters).
    var coreKind: FeedCounterKind {
        switch self {
        case .none: return .none
        case .new: return .new
        case .unplayed: return .unplayed
        case .downloaded: return .downloaded
        case .downloadedUnplayed: return .downloadedUnplayed
        }
    }
}

/// Grid cell: cover art, title, counter badge (Android SubscriptionViewHolder grid layout).
struct SubscriptionGridCell: View {
    let feed: PodcastFeed
    let title: String
    let count: Int
    /// Android pref_show_subscription_title; VoiceOver keeps the title either way.
    var showTitle: Bool = true

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
            if showTitle {
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
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

    /// Feed artwork with the same placeholder as the grid (also used by the feed page header).
    @ViewBuilder
    static func feedArtwork(_ feed: PodcastFeed) -> some View {
        if let raw = feed.imageUrl, let url = URL(string: raw) {
            AppAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
        } else {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: LocalFolderFeed.isLocalFolderFeed(feed) ? "folder.fill" : "mic")
                    .foregroundStyle(.secondary)
            }
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
