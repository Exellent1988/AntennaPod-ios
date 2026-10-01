import SwiftUI

struct EchoView: View {
    @EnvironmentObject private var store: PodcastStore

    private var summary: EchoYearSummary {
        store.echoYearSummary()
    }

    var body: some View {
        List {
            if summary.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Echo for \(summary.year) yet"),
                    systemImage: "sparkles.rectangle.stack",
                    description: Text(
                        "Play episodes and mark them played this calendar year. Echo uses the same approximate playback data as Statistics."
                    )
                )
            } else {
                Section {
                    LabeledContent("Year") {
                        Text("\(summary.year)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Played episodes") {
                        Text("\(summary.playedEpisodeCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Approx. listening time") {
                        Text(StatisticsView.formatDuration(summary.approximateListenedSeconds))
                            .foregroundStyle(.secondary)
                    }
                    if summary.favoritesCountThisYear > 0 || summary.favoritesTotalCount > 0 {
                        LabeledContent("Favorites this year") {
                            Text("\(summary.favoritesCountThisYear)")
                                .foregroundStyle(.secondary)
                        }
                        if summary.favoritesTotalCount != summary.favoritesCountThisYear {
                            LabeledContent("Favorites total") {
                                Text("\(summary.favoritesTotalCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Your \(summary.year) in podcasts")
                } footer: {
                    Text(Self.approximationFootnote)
                }

                if !summary.topPodcasts.isEmpty {
                    Section {
                        ForEach(Array(summary.topPodcasts.enumerated()), id: \.element.id) { index, feed in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(index + 1).")
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 24, alignment: .trailing)
                                    Text(feed.feedTitle)
                                        .font(.body)
                                    Spacer(minLength: 8)
                                    Text(StatisticsView.formatDuration(feed.approximateListenedSeconds))
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
                        Text("Sorted by approximate listening time, then play count. Up to 10.")
                    }
                }
            }
        }
        .navigationTitle("Echo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !summary.isEmpty {
                    ShareLink(item: Self.shareText(for: summary)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private static var approximationFootnote: String {
        String(localized: "Approximate: played episodes this year use lastPlayedAt (else updatedAt) and saved duration from playback.json — same limits as Statistics. Does not count rewinds, playback speed, or re-listens. Calendar year follows the device calendar.")
    }

    private static func feedSubtitle(_ feed: EchoFeedStats) -> String {
        String(localized: "\(feed.playedEpisodeCount) played")
    }

    static func shareText(for summary: EchoYearSummary) -> String {
        var lines: [String] = [
            String(localized: "AntennaPod Echo \(summary.year)"),
            "",
            String(localized: "Played episodes: \(summary.playedEpisodeCount)"),
            String(localized: "Approx. listening time: \(StatisticsView.formatDuration(summary.approximateListenedSeconds))"),
        ]
        if summary.favoritesCountThisYear > 0 || summary.favoritesTotalCount > 0 {
            lines.append(String(localized: "Favorites this year: \(summary.favoritesCountThisYear)"))
            if summary.favoritesTotalCount != summary.favoritesCountThisYear {
                lines.append(String(localized: "Favorites total: \(summary.favoritesTotalCount)"))
            }
        }
        if !summary.topPodcasts.isEmpty {
            lines.append("")
            lines.append(String(localized: "Top podcasts:"))
            for (index, feed) in summary.topPodcasts.enumerated() {
                let duration = StatisticsView.formatDuration(feed.approximateListenedSeconds)
                lines.append(
                    String(localized: "\(index + 1). \(feed.feedTitle) — \(duration) (\(feed.playedEpisodeCount) played)")
                )
            }
        }
        lines.append("")
        lines.append(String(localized: "(Approximate — same limits as AntennaPod Statistics.)"))
        return lines.joined(separator: "\n")
    }
}
