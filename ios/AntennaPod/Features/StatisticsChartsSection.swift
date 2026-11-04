import Charts
import PodcastCore
import SwiftUI

/// Android Statistics charts: pie of listening time per podcast (selected time range) and bars
/// per year, or per month of one year.
struct StatisticsChartsSection: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @State private var barMode: BarMode = .years
    @State private var monthYear = Calendar.current.component(.year, from: Date())

    enum BarMode: Hashable { case years, months }

    var body: some View {
        let stats = store.listeningStatistics(in: settings.statisticsTimeRange)
        let slices = StatisticsChartData.pieSlices(
            stats.topPodcasts.map { (label: $0.feedTitle, seconds: $0.approximateListenedSeconds) },
            otherLabel: String(localized: "Other podcasts"))
        let years = store.yearlyListening()

        if !slices.isEmpty {
            Section {
                Chart(Array(slices.enumerated()), id: \.offset) { _, slice in
                    SectorMark(angle: .value("Time", slice.seconds), innerRadius: .ratio(0.5), angularInset: 1.5)
                        .foregroundStyle(by: .value("Podcast", slice.label))
                        .accessibilityLabel(slice.label)
                        .accessibilityValue(StatisticsView.formatDuration(slice.seconds))
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 260)
                .padding(.vertical, 8)
                .accessibilityIdentifier("statisticsPieChart")
            } header: {
                Text("Listening time per podcast")
            } footer: {
                Text("Selected time range. Same estimate as Totals.")
            }
        }

        if !years.isEmpty {
            Section {
                Picker("Chart", selection: $barMode) {
                    Text("Years").tag(BarMode.years)
                    Text("Months").tag(BarMode.months)
                }
                .pickerStyle(.segmented)
                if barMode == .months {
                    Picker("Year", selection: $monthYear) {
                        ForEach(years.map(\.year), id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                barChart(years: years)
                    .frame(height: 220)
                    .padding(.vertical, 8)
            } header: {
                Text("Listening time over time")
            } footer: {
                Text("Hours per year or per month. The time range does not apply here; Reset and Include marked as played do.")
            }
        }
    }

    @ViewBuilder
    private func barChart(years: [StatisticsParity.YearTotal]) -> some View {
        switch barMode {
        case .years:
            Chart(years.reversed(), id: \.year) { y in
                BarMark(x: .value("Year", String(y.year)), y: .value("Hours", y.seconds / 3600))
                    .accessibilityLabel(String(y.year))
                    .accessibilityValue(StatisticsView.formatDuration(y.seconds))
            }
            .accessibilityIdentifier("statisticsYearBars")
        case .months:
            let months = store.monthlyListening(year: monthYear)
            let symbols = Calendar.current.shortMonthSymbols
            Chart(Array(months.enumerated()), id: \.offset) { i, secs in
                BarMark(x: .value("Month", symbols[i]), y: .value("Hours", secs / 3600))
                    .accessibilityLabel(symbols[i])
                    .accessibilityValue(StatisticsView.formatDuration(secs))
            }
            .accessibilityIdentifier("statisticsMonthBars")
        }
    }
}
