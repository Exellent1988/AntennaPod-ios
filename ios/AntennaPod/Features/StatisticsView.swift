import SwiftUI
import UIKit

struct StatisticsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showResetConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private var stats: ListeningStatistics {
        store.listeningStatistics(in: settings.statisticsTimeRange)
    }

    /// Unfiltered total — distinguishes “no data ever” from “none in this range” / after reset.
    private var allTimeStats: ListeningStatistics {
        store.listeningStatistics(in: .allTime)
    }

    /// Same rows Statistics can count (History catalog). A playback.json row whose
    /// episode is gone (local file removed on rescan, left after Clear history) is
    /// never counted, so it must not turn "No statistics yet" into "in this range".
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
                    if let since = Self.resetSinceFootnote(epochMs: settings.statisticsResetAtEpochMs) {
                        Text(since)
                    }
                }
            }

            if stats.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "chart.bar",
                    description: Text(emptyDescription)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(emptyTitle)
                .accessibilityValue(emptyDescription)
            } else {
                Section {
                    LabeledContent("Played episodes") {
                        Text("\(stats.playedEpisodeCount)")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Played episodes"))
                    .accessibilityValue("\(stats.playedEpisodeCount)")

                    if stats.inProgressEpisodeCount > 0 {
                        LabeledContent("In progress") {
                            Text("\(stats.inProgressEpisodeCount)")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "In progress"))
                        .accessibilityValue("\(stats.inProgressEpisodeCount)")
                        .accessibilityHint(String(localized: "Episodes with saved playback progress that are not marked played. Same time range and Reset baseline as Totals. Their saved position contributes to Approx. listening time."))
                    }

                    LabeledContent("Approx. listening time") {
                        Text(Self.formatDuration(stats.approximateListenedSeconds))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Approx. listening time"))
                    .accessibilityValue(Self.formatDuration(stats.approximateListenedSeconds))
                    .accessibilityHint(String(localized: "Wall-clock estimate from saved duration or position, not speed-adjusted"))
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
                            .accessibilityLabel(
                                "\(index + 1). \(feed.feedTitle), \(Self.formatDuration(feed.approximateListenedSeconds))"
                            )
                            .accessibilityValue(Self.feedSubtitle(feed))
                            .accessibilityHint(String(localized: "Per-feed rollup using the same wall-clock estimate as Totals"))
                        }
                    } header: {
                        Text("Top podcasts")
                    } footer: {
                        Text(Self.topPodcastsFootnote)
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !stats.isEmpty {
                        Button {
                            copyStatistics()
                        } label: {
                            Label("Copy statistics", systemImage: "doc.on.clipboard")
                        }
                        .accessibilityLabel(String(localized: "Copy statistics"))
                        .accessibilityHint(
                            String(localized: "Copies the same plain-text summary as Share, using the selected Statistics time range and Reset baseline.")
                        )

                        ShareLink(item: Self.shareText(for: stats, range: settings.statisticsTimeRange)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityHint(
                            String(localized: "Shares the same plain-text summary using the selected Statistics time range and Reset baseline.")
                        )
                    }
                    Button("Reset statistics", role: .destructive) {
                        showResetConfirm = true
                    }
                    .accessibilityHint(String(localized: "Asks for confirmation, then sets a baseline so Statistics and Echo count only episodes last touched after now. Does not clear History, progress, played flags, downloads, queue, or favorites. Filters playback.json stamps — unlike Android there is no separate played-duration counter. Episodes last played before the reset reappear only when played again."))
                } label: {
                    Label("Statistics actions", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "Statistics actions"))
                .accessibilityHint(
                    stats.isEmpty
                        ? String(localized: "Reset Statistics baseline. Copy and Share appear when this time range has totals to export.")
                        : String(localized: "Copy or share the same plain-text summary, or reset Statistics baseline")
                )
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
        .confirmationDialog(
            "Reset statistics?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset statistics", role: .destructive) {
                settings.resetStatisticsBaseline()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.resetConfirmMessage)
        }
    }

    private func copyStatistics() {
        let text = Self.shareText(for: stats, range: settings.statisticsTimeRange)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Statistics copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private var emptyTitle: String {
        if !hasAnyPlaybackHistory {
            return String(localized: "No statistics yet")
        }
        if hasActiveReset && allTimeStats.isEmpty {
            return String(localized: "No statistics since reset")
        }
        return String(localized: "No statistics in this range")
    }

    private var emptyDescription: String {
        if !hasAnyPlaybackHistory {
            return String(localized: "Play episodes or mark them played. Totals are derived from saved playback progress — wall-clock duration or position in playback.json, not a separate cumulative counter. Streaming with no saved progress is not counted.")
        }
        if hasActiveReset && allTimeStats.isEmpty {
            return String(localized: "History still has older playback, but Statistics only counts stamps after the last Reset. Play again or choose a wider time range. Reset does not clear History.")
        }
        return String(localized: "No played or in-progress episodes with a last-played timestamp in this range (and after any Reset baseline). Try All time or another period.")
    }

    private static var approximationFootnote: String {
        String(localized: "Approximate wall-clock time: played episodes use saved duration (position cleared when marked played); in-progress use saved position. Not speed-adjusted — 1.5× does not shrink totals. Does not count rewinds, re-listens, or streaming with no saved progress. Played with unknown duration contribute 0. Derived from playback.json — no separate cumulative counter. Time range + optional Reset use lastPlayedAt (else updatedAt) — episode-level stamps, not per-session listen windows. History size limit may drop oldest entries and their stats.")
    }

    private static var topPodcastsFootnote: String {
        String(localized: "Sorted by approximate listening time, then play count. Same wall-clock estimate as Totals per feed. Queue-only episodes without a known feed count in Totals but may omit a row here.")
    }

    private static var resetConfirmMessage: String {
        String(localized: "Sets a baseline timestamp so Statistics and Echo count only episodes last touched after now. Does not clear History, progress, played flags, downloads, queue, or favorites. Unlike Android there is no separate played-duration counter — this filters playback.json stamps. Episodes last played before the reset reappear only when played again.")
    }

    private static func rangeFootnote(for range: StatisticsTimeRange) -> String {
        switch range {
        case .allTime:
            return String(localized: "All saved playback progress still in playback.json (since first progress or last Reset). Calendar follows the device.")
        case .thisWeek, .thisMonth, .thisYear:
            return String(localized: "Filtered by lastPlayedAt (else updatedAt) in the selected device-calendar period, and after any Reset baseline.")
        }
    }

    /// Shared with Echo empty/footer honesty after Statistics Reset.
    static func resetSinceFootnote(epochMs: Int64) -> String? {
        guard epochMs > 0 else { return nil }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Counting since \(formatted) (after last Reset). History and progress stay.")
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

    static func shareText(for stats: ListeningStatistics, range: StatisticsTimeRange) -> String {
        let title: String
        switch range {
        case .thisWeek:
            title = String(localized: "AntennaPod Statistics — This week")
        case .thisMonth:
            title = String(localized: "AntennaPod Statistics — This month")
        case .thisYear:
            title = String(localized: "AntennaPod Statistics — This year")
        case .allTime:
            title = String(localized: "AntennaPod Statistics — All time")
        }
        var lines: [String] = [
            title,
            "",
            String(localized: "Played episodes: \(stats.playedEpisodeCount)"),
            String(localized: "Approx. listening time: \(formatDuration(stats.approximateListenedSeconds))"),
        ]
        if stats.inProgressEpisodeCount > 0 {
            lines.insert(
                String(localized: "In progress: \(stats.inProgressEpisodeCount)"),
                at: 3
            )
        }
        if !stats.topPodcasts.isEmpty {
            lines.append("")
            lines.append(String(localized: "Top podcasts:"))
            for (index, feed) in stats.topPodcasts.enumerated() {
                let duration = formatDuration(feed.approximateListenedSeconds)
                if feed.inProgressEpisodeCount > 0 {
                    lines.append(
                        String(
                            localized: "\(index + 1). \(feed.feedTitle) — \(duration) (\(feed.playedEpisodeCount) played · \(feed.inProgressEpisodeCount) in progress)"
                        )
                    )
                } else {
                    lines.append(
                        String(localized: "\(index + 1). \(feed.feedTitle) — \(duration) (\(feed.playedEpisodeCount) played)")
                    )
                }
            }
        }
        lines.append("")
        lines.append(
            String(
                localized: "(Approximate wall-clock — played use saved duration; in-progress use position. Not speed-adjusted. No rewinds, re-listens, or streaming without saved progress. Coarse episode stamps — lastPlayedAt else updatedAt; optional Reset baseline.)"
            )
        )
        return lines.joined(separator: "\n")
    }
}
