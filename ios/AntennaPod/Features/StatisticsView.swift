import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var store: PodcastStore

    private var stats: ListeningStatistics {
        store.listeningStatistics
    }

    var body: some View {
        List {
            if stats.isEmpty {
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.bar",
                    description: Text("Play episodes or mark them played. Totals are derived from saved playback progress.")
                )
            } else {
                Section {
                    LabeledContent("Played episodes") {
                        Text("\(stats.playedEpisodeCount)")
                            .foregroundStyle(.secondary)
                    }
                    if stats.inProgressEpisodeCount > 0 {
                        LabeledContent("In progress") {
                            Text("\(stats.inProgressEpisodeCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Approx. listening time") {
                        Text(Self.formatDuration(stats.approximateListenedSeconds))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Totals")
                } footer: {
                    Text(Self.approximationFootnote)
                }

                if !stats.topPodcasts.isEmpty {
                    Section {
                        ForEach(Array(stats.topPodcasts.enumerated()), id: \.element.id) { index, feed in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(index + 1).")
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 24, alignment: .trailing)
                                    Text(feed.feedTitle)
                                        .font(.body)
                                    Spacer(minLength: 8)
                                    Text(Self.formatDuration(feed.approximateListenedSeconds))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(Self.feedSubtitle(feed))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 32)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Top podcasts")
                    } footer: {
                        Text("Sorted by approximate listening time, then play count.")
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var approximationFootnote: String {
        String(localized: "Approximate: played episodes use saved duration (position is cleared when marked played); in-progress use saved position. Does not count rewinds, playback speed, or re-listens. Derived from playback.json — no separate cumulative counter.")
    }

    private static func feedSubtitle(_ feed: FeedListeningStats) -> String {
        var parts: [String] = []
        if feed.playedEpisodeCount > 0 {
            parts.append(String(localized: "\(feed.playedEpisodeCount) played"))
        }
        if feed.inProgressEpisodeCount > 0 {
            parts.append(String(localized: "\(feed.inProgressEpisodeCount) in progress"))
        }
        return parts.joined(separator: " · ")
    }

    /// Human-readable duration for stats (hours / minutes). Integers via String Catalog (`%lld`); no hardcoded decimal commas.
    static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        }
        if minutes > 0 {
            return String(localized: "\(minutes) min")
        }
        if total > 0 {
            return String(localized: "\(total)s")
        }
        return String(localized: "0 min")
    }
}
