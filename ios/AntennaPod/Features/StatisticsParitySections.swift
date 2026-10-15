import PodcastCore
import SwiftUI

/// Android Statistics Years + Downloads tabs, shown as sections below Top podcasts.
struct StatisticsParitySections: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService

    var body: some View {
        StatisticsChartsSection()
        let years = store.yearlyListening()
        if !years.isEmpty {
            Section {
                ForEach(years, id: \.year) { year in
                    LabeledContent(String(year.year)) {
                        Text(StatisticsView.formatDuration(year.seconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Years")
            } footer: {
                Text("Listening time per calendar year. The time range does not apply here; Reset and Include marked as played do.")
            }
        }

        let totals = downloads.storageByPodcast(store: store)
        Section {
            if totals.isEmpty {
                Text("No downloaded episodes")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Total") {
                    Text(Self.summary(episodes: totals.reduce(0) { $0 + $1.episodes },
                                      bytes: totals.reduce(0) { $0 + $1.bytes }))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                ForEach(totals, id: \.key) { feed in
                    LabeledContent(feed.title) {
                        Text(Self.summary(episodes: feed.episodes, bytes: feed.bytes))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Downloads")
        }
    }

    static func summary(episodes: Int, bytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return String(localized: "\(episodes) episodes · \(size)")
    }
}
