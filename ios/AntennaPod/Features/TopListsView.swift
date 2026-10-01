import SwiftUI

/// Apple iTunes top podcast charts (Quick discovery). Pull-to-refresh; Subscribe via feed URL pipeline.
struct TopListsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var results: [ItunesPodcastResult] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var didLoad = false
    @State private var subscribingFeedUrl: String?

    private let service = ItunesTopListService()

    private var countryCode: String {
        settings.resolvedChartsCountryCode
    }

    private var countryLabel: String {
        let code = countryCode.uppercased()
        let name = Locale.current.localizedString(forRegionCode: code) ?? code
        return "\(name) (\(code))"
    }

    var body: some View {
        List {
            Section {
                Text("Top podcasts on Apple Charts for \(countryLabel). No API key — public iTunes RSS. Change country under Settings → Discovery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    Button("Retry") {
                        Task { await loadCharts() }
                    }
                }
            }

            if didLoad && !isLoading && results.isEmpty && loadError == nil {
                Section {
                    ContentUnavailableView(
                        "No chart results",
                        systemImage: "chart.bar",
                        description: Text("iTunes returned no podcasts for this country, or feed URLs could not be resolved. Try another country in Settings.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !results.isEmpty {
                Section("Top \(results.count)") {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        DiscoveryResultRow(
                            title: "\(index + 1). \(item.title)",
                            author: item.author,
                            artworkURL: item.artworkURL,
                            feedUrl: item.feedUrl,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl },
                            isSubscribing: subscribingFeedUrl == item.feedUrl,
                            onSubscribe: {
                                Task { await subscribe(item.feedUrl) }
                            }
                        )
                    }
                }
            }

            if let error = store.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && results.isEmpty {
                ProgressView("Loading charts…")
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
    }

    @MainActor
    private func loadCharts() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let found = try await service.loadTopList(country: countryCode)
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

    @MainActor
    private func subscribe(_ feedUrl: String) async {
        guard !feedUrl.isEmpty else { return }
        subscribingFeedUrl = feedUrl
        defer { subscribingFeedUrl = nil }
        await store.subscribe(feedUrl: feedUrl)
    }
}

/// Compact Home preview of top charts (Quick discovery).
struct HomeTopListsPreview: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var preview: [ItunesPodcastResult] = []
    @State private var loadError: String?
    @State private var isLoading = false

    private let service = ItunesTopListService()
    private let limit = 5

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
                }
            }
        }
        .task {
            await loadPreview()
        }
        .onChange(of: settings.chartsCountryCode) { _, _ in
            Task { await loadPreview() }
        }
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let found = try await service.loadTopList(
                country: settings.resolvedChartsCountryCode,
                limit: limit
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
