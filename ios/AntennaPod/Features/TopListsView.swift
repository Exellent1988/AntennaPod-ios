import SwiftUI

/// Apple iTunes top podcast charts (Quick discovery). Pull-to-refresh; Preview → Confirm Subscribe.
struct TopListsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls

    @State private var results: [ItunesPodcastResult] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var didLoad = false
    @State private var previewRequest: FeedPreviewRequest?

    private let service = ItunesTopListService()

    private var countryCode: String {
        settings.resolvedChartsCountryCode
    }

    private var countryLabel: String {
        let code = countryCode.uppercased()
        let name = Locale.current.localizedString(forRegionCode: code) ?? code
        return "\(name) (\(code))"
    }

    private var chartsHelpText: String {
        let template = String(
            localized: "Top podcasts on Apple Charts for %@. No API key — public iTunes RSS. Change country under Settings → Discovery."
        )
        return String(format: template, locale: .current, countryLabel)
    }

    var body: some View {
        List {
            Section {
                Text(chartsHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chartsHelpText)
                    .accessibilityHint(
                        String(localized: "Explains the chart source and where to change the country")
                    )
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "Chart loading error") + ", " + loadError
                        )
                    Button("Retry") {
                        Task { await loadCharts() }
                    }
                    .accessibilityHint(String(localized: "Loads the podcast charts again"))
                }
            }

            if didLoad && !isLoading && results.isEmpty && loadError == nil {
                Section {
                    ContentUnavailableView(
                        "No chart results",
                        systemImage: "chart.bar",
                        description: Text("iTunes returned no podcasts for this country, or feed URLs could not be resolved. Try another country in Settings.")
                    )
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                }
            }

            if !results.isEmpty {
                Section(String(localized: "Top \(results.count)")) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        DiscoveryResultRow(
                            title: "\(index + 1). \(item.title)",
                            author: item.author,
                            artworkURL: item.artworkURL,
                            feedUrl: item.feedUrl,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl },
                            onSelect: {
                                previewRequest = FeedPreviewRequest(
                                    feedUrl: item.feedUrl,
                                    hintTitle: item.title,
                                    hintAuthor: item.author,
                                    hintArtworkURL: item.artworkURL
                                )
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $previewRequest) { request in
            FeedPreviewView(request: request)
        }
        .overlay {
            if isLoading && results.isEmpty {
                ProgressView("Loading charts…")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Loading podcast charts"))
                    .accessibilityAddTraits(.updatesFrequently)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .refreshable {
            await loadCharts()
        }
        .task {
            if !didLoad {
                await loadCharts()
            }
        }
        .onChange(of: settings.chartsCountryCode) { _, _ in
            Task { await loadCharts() }
        }
        .onChange(of: settings.discoverChartsLimit) { _, _ in
            Task { await loadCharts() }
        }
        .onChange(of: parental.hideExplicitCharts) { _, _ in
            Task { await loadCharts() }
        }
        .onChange(of: parental.isEnabled) { _, _ in
            Task { await loadCharts() }
        }
    }

    @MainActor
    private func loadCharts() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let found = try await service.loadTopList(
                country: countryCode,
                limit: settings.discoverChartsLimit.rowCap,
                includeExplicit: !parental.shouldHideExplicitCharts
            )
            results = found
            didLoad = true
        } catch is CancellationError {
            // ignore
        } catch {
            results = []
            didLoad = true
            loadError = error.localizedDescription
        }
    }
}

/// Compact Home preview of top charts (Quick discovery). Soft-cap via `homeDiscoverPreviewLimit`
/// (not full TopListsView / `discoverChartsLimit`).
struct HomeTopListsPreview: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls

    @State private var preview: [ItunesPodcastResult] = []
    @State private var loadError: String?
    @State private var isLoading = false

    private let service = ItunesTopListService()

    /// Soft-cap from `AppSettings.homeDiscoverPreviewLimit` (3/5/8/10, default 5). Full Discover /
    /// TopListsView uses `AppSettings.discoverChartsLimit` (`DiscoverChartsLimit` 10/25/50/100, default 25).
    private var limit: Int {
        let allowed = Set(HomePreviewLimit.allCases.map(\.rawValue))
        let raw = settings.homeDiscoverPreviewLimit.rawValue
        return allowed.contains(raw) ? raw : HomePreviewLimit.five.rawValue
    }

    var body: some View {
        Group {
            if isLoading && preview.isEmpty && loadError == nil {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading charts…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let loadError, preview.isEmpty {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !preview.isEmpty {
                ForEach(Array(preview.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(item.author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if store.feeds.contains(where: { $0.feedUrl == item.feedUrl }) {
                            Text("Subscribed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        previewAccessibilityLabel(
                            index: index,
                            item: item,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl }
                        )
                    )
                }
            }
        }
        .task {
            await loadPreview()
        }
        .onChange(of: settings.chartsCountryCode) { _, _ in
            Task { await loadPreview() }
        }
        .onChange(of: settings.homeDiscoverPreviewLimit) { _, _ in
            Task { await loadPreview() }
        }
        .onChange(of: parental.hideExplicitCharts) { _, _ in
            Task { await loadPreview() }
        }
        .onChange(of: parental.isEnabled) { _, _ in
            Task { await loadPreview() }
        }
    }

    private func previewAccessibilityLabel(
        index: Int,
        item: ItunesPodcastResult,
        isSubscribed: Bool
    ) -> String {
        var parts = [String(localized: "Chart position") + " \(index + 1)", item.title]
        if !item.author.isEmpty {
            parts.append(item.author)
        }
        if isSubscribed {
            parts.append(String(localized: "Subscribed"))
        }
        return parts.joined(separator: ", ")
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let found = try await service.loadTopList(
                country: settings.resolvedChartsCountryCode,
                limit: limit,
                includeExplicit: !parental.shouldHideExplicitCharts
            )
            preview = found
        } catch is CancellationError {
            // ignore
        } catch {
            preview = []
            loadError = error.localizedDescription
        }
    }
}
