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

/// Grid cell modelled on Android subscription_grid_item.xml + SubscriptionViewHolder.bind:
/// a 12dp-rounded card; square cover (fitCenter on non_square_icon_background #22777777);
/// counter pill top-right (TextPill: bg_pill_translucent #D2404040, 18dp corners, 8dp margin,
/// 8dp side padding, white 14sp); title below inside the card (2 lines, 16/15/14sp and 16/8dp padding
/// by column count); with titles off a cover-less feed shows its title on #55333333 (fallbackTitleLabel).
struct SubscriptionGridCell: View {
    let feed: PodcastFeed
    let title: String
    let count: Int
    /// Android pref_show_subscription_title; VoiceOver keeps the title either way.
    var showTitle: Bool = true
    /// Android SubscriptionViewHolder.bind columnCount (text size / padding).
    var columns: Int = 3

    /// Android: textSize 16 (2 columns), 15 (3), 14 (4–5).
    static func titleFontSize(columns: Int) -> CGFloat {
        columns <= 2 ? 16 : (columns == 3 ? 15 : 14)
    }
    /// Android: textPadding 16 when columns <= 3, else 8 (dp; halved for the smaller iOS cells).
    static func titlePadding(columns: Int) -> CGFloat {
        columns <= 3 ? 8 : 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255).opacity(0x22 / 255)
                artwork
                if count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(Color(red: 0x40 / 255, green: 0x40 / 255, blue: 0x40 / 255).opacity(0xD2 / 255),
                                    in: Capsule())
                        .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if showTitle {
                Text(title)
                    .font(.system(size: Self.titleFontSize(columns: columns)))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Self.titlePadding(columns: columns))
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
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
                    image.resizable().aspectRatio(contentMode: .fit)
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

    /// Android CoverLoader placeholder: fallbackTitleLabel (white title on #55333333) when the grid title is
    /// hidden; with titles shown the title already sits below, so only the icon placeholder remains.
    @ViewBuilder
    private var placeholder: some View {
        if showTitle {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: LocalFolderFeed.isLocalFolderFeed(feed) ? "folder.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        } else {
            ZStack {
                Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255).opacity(0x55 / 255)
                Text(title)
                    .font(.system(size: Self.titleFontSize(columns: columns)))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.6)
                    .padding(Self.titlePadding(columns: columns))
            }
        }
    }
}
