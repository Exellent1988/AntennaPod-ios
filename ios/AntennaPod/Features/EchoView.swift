import SwiftUI
import UIKit

struct EchoView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private var summary: EchoYearSummary {
        store.echoYearSummary(in: settings.statisticsTimeRange)
    }

    /// All-time Echo after any Reset baseline — empty after Reset even when History has older plays.
    private var allTimeSummary: EchoYearSummary {
        store.echoYearSummary(in: .allTime)
    }

    /// Raw History catalog — distinguishes “never listened” from “empty only because of Reset”.
    private var hasAnyPlaybackHistory: Bool {
        !store.historyEpisodes.isEmpty
    }

    private var hasActiveReset: Bool {
        settings.statisticsResetAtEpochMs > 0
    }

    var body: some View {
        List {
            Section {
                Picker(selection: $settings.statisticsTimeRange) {
                    ForEach(StatisticsTimeRange.allCases) { range in
                        Text(range.shortLabel).tag(range)
                    }
                } label: {
                    Text("Time range")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "Statistics time range"))
                .accessibilityValue(settings.statisticsTimeRange.label)
                .accessibilityHint(String(localized: "Chooses which period Statistics and Echo show together. Shared setting. Uses the device calendar. Optional Reset baseline still applies."))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.rangeFootnote(for: settings.statisticsTimeRange))
                    if let since = StatisticsView.resetSinceFootnote(epochMs: settings.statisticsResetAtEpochMs) {
                        Text(since)
                    }
                }
            }

            if summary.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "sparkles.rectangle.stack",
                    description: Text(emptyDescription)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(emptyTitle)
                .accessibilityValue(emptyDescription)
            } else {
                Section {
                    if settings.statisticsTimeRange == .thisYear {
                        LabeledContent("Year") {
                            Text("\(summary.year)")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Year"))
                        .accessibilityValue("\(summary.year)")
                    } else {
                        LabeledContent("Period") {
                            Text(settings.statisticsTimeRange.label)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Period"))
                        .accessibilityValue(settings.statisticsTimeRange.label)
                    }
                    LabeledContent("Played episodes") {
                        Text("\(summary.playedEpisodeCount)")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Played episodes"))
                    .accessibilityValue("\(summary.playedEpisodeCount)")

                    LabeledContent("Approx. listening time") {
                        Text(StatisticsView.formatDuration(summary.approximateListenedSeconds))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Approx. listening time"))
                    .accessibilityValue(StatisticsView.formatDuration(summary.approximateListenedSeconds))
                    .accessibilityHint(
                        String(localized: "Wall-clock estimate from saved duration or position, not speed-adjusted")
                    )
                    if summary.favoritesCountThisYear > 0 || summary.favoritesTotalCount > 0 {
                        LabeledContent(favoritesInRangeLabel) {
                            Text("\(summary.favoritesCountThisYear)")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(favoritesInRangeLabel)
                        .accessibilityValue("\(summary.favoritesCountThisYear)")
                        .accessibilityHint(String(localized: "Count of currently starred episodes whose favorited-at stamp falls in this time range and after any Statistics Reset. Same Favorites list as the Favorites screen — orphans in favorites.json are not counted."))
                        if summary.favoritesTotalCount != summary.favoritesCountThisYear {
                            LabeledContent("Favorites total") {
                                Text("\(summary.favoritesTotalCount)")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(String(localized: "Favorites total"))
                            .accessibilityValue("\(summary.favoritesTotalCount)")
                            .accessibilityHint(String(localized: "All currently starred episodes in any year. Not limited to this time range. Same Favorites list as the Favorites screen — orphans in favorites.json are not counted."))
                        }
                    }
                } header: {
                    Text(sectionHeader)
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
                            .accessibilityLabel(
                                "\(index + 1). \(feed.feedTitle), \(StatisticsView.formatDuration(feed.approximateListenedSeconds))"
                            )
                            .accessibilityValue(Self.feedSubtitle(feed))
                            .accessibilityHint(
                                String(localized: "Per-feed rollup using the same wall-clock estimate as Totals")
                            )
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
            ToolbarItemGroup(placement: .primaryAction) {
                if !summary.isEmpty {
                    Button {
                        copyEcho()
                    } label: {
                        Label("Copy Echo", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityLabel(String(localized: "Copy Echo"))
                    .accessibilityHint(
                        String(localized: "Copies the same plain-text summary as Share, using the selected Statistics time range and Reset baseline.")
                    )

                    ShareLink(item: Self.shareText(for: summary, range: settings.statisticsTimeRange)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityHint(
                        String(localized: "Shares the same plain-text Echo summary using the selected Statistics time range and Reset baseline.")
                    )
                }
            }
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCopiedAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedAlertMessage)
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTick)
    }

    private func copyEcho() {
        let text = Self.shareText(for: summary, range: settings.statisticsTimeRange)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Echo summary copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private var sectionHeader: String {
        switch settings.statisticsTimeRange {
        case .thisWeek:
            return String(localized: "Your week in podcasts")
        case .thisMonth:
            return String(localized: "Your month in podcasts")
        case .thisYear:
            return String(localized: "Your \(summary.year) in podcasts")
        case .allTime:
            return String(localized: "Your podcasts — all time")
        }
    }

    private var favoritesInRangeLabel: String {
        switch settings.statisticsTimeRange {
        case .thisWeek:
            return String(localized: "Favorites this week")
        case .thisMonth:
            return String(localized: "Favorites this month")
        case .thisYear:
            return String(localized: "Favorites this year")
        case .allTime:
            return String(localized: "Favorites")
        }
    }

    private var emptyTitle: String {
        if !hasAnyPlaybackHistory {
            if settings.statisticsTimeRange == .thisYear {
                return String(localized: "No Echo for \(summary.year) yet")
            }
            return String(localized: "No Echo yet")
        }
        if hasActiveReset && allTimeSummary.isEmpty {
            return String(localized: "No Echo since reset")
        }
        return String(localized: "No Echo in this range")
    }

    private var emptyDescription: String {
        if !hasAnyPlaybackHistory {
            return String(localized: "Play episodes and mark them played. Echo uses the same approximate playback data as Statistics.")
        }
        if hasActiveReset && allTimeSummary.isEmpty {
            return String(localized: "History still has older playback, but Echo only counts stamps after the last Statistics Reset. Play again or choose a wider time range. Reset does not clear History.")
        }
        return String(localized: "No played episodes with a last-played timestamp in this range (and after any Reset baseline). Try All time or another period. Echo uses the same approximate playback data as Statistics.")
    }

    private static var approximationFootnote: String {
        String(localized: "Approximate wall-clock: played episodes use lastPlayedAt (else updatedAt) and saved duration from playback.json — same limits as Statistics (incl. Reset baseline). Not speed-adjusted. Does not count rewinds, re-listens, or streaming without saved progress. Time range follows the device calendar; stamps are episode-level, not per-session.")
    }

    private static func rangeFootnote(for range: StatisticsTimeRange) -> String {
        switch range {
        case .allTime:
            return String(localized: "All saved played episodes and favorites in playback.json / favorites.json since first progress or last Statistics Reset. Calendar follows the device. Shared with Statistics.")
        case .thisWeek, .thisMonth, .thisYear:
            return String(localized: "Filtered by lastPlayedAt (else updatedAt) / favoritedAt in the selected device-calendar period, and after any Statistics Reset baseline. Shared with Statistics.")
        }
    }

    private static func feedSubtitle(_ feed: EchoFeedStats) -> String {
        String(localized: "\(feed.playedEpisodeCount) played")
    }

    static func shareText(for summary: EchoYearSummary, range: StatisticsTimeRange) -> String {
        let title: String
        switch range {
        case .thisYear:
            title = String(localized: "AntennaPod Echo \(summary.year)")
        case .thisWeek:
            title = String(localized: "AntennaPod Echo — This week")
        case .thisMonth:
            title = String(localized: "AntennaPod Echo — This month")
        case .allTime:
            title = String(localized: "AntennaPod Echo — All time")
        }
        var lines: [String] = [
            title,
            "",
            String(localized: "Played episodes: \(summary.playedEpisodeCount)"),
            String(localized: "Approx. listening time: \(StatisticsView.formatDuration(summary.approximateListenedSeconds))"),
        ]
        if summary.favoritesCountThisYear > 0 || summary.favoritesTotalCount > 0 {
            let favLabel: String
            switch range {
            case .thisWeek:
                favLabel = String(localized: "Favorites this week: \(summary.favoritesCountThisYear)")
            case .thisMonth:
                favLabel = String(localized: "Favorites this month: \(summary.favoritesCountThisYear)")
            case .thisYear:
                favLabel = String(localized: "Favorites this year: \(summary.favoritesCountThisYear)")
            case .allTime:
                favLabel = String(localized: "Favorites: \(summary.favoritesCountThisYear)")
            }
            lines.append(favLabel)
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
        lines.append(String(localized: "(Approximate wall-clock — same limits as AntennaPod Statistics, including Reset baseline.)"))
        return lines.joined(separator: "\n")
    }
}
