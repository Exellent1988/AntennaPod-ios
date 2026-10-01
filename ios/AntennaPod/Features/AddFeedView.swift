import SwiftUI

/// Add podcast: Apple Podcasts / iTunes search + subscribe-by-URL.
struct AddFeedView: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .search
    @State private var urlText = "https://"
    @FocusState private var urlFocused: Bool

    @State private var searchText = ""
    @State private var results: [ItunesPodcastResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?
    @State private var subscribingFeedUrl: String?

    private let searcher = ItunesSearchService()
    private let debounceNs: UInt64 = 400_000_000 // 400 ms

    private enum AddMode: String, CaseIterable, Identifiable {
        case search = "Search"
        case url = "Feed URL"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(AddMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch mode {
                case .search:
                    searchContent
                case .url:
                    urlContent
                }
            }
            .navigationTitle("Add podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        searchTask?.cancel()
                        dismiss()
                    }
                }
                if mode == .url {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Subscribe") {
                            Task { await subscribeURL() }
                        }
                        .disabled(store.isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    // MARK: - Search (Apple Podcasts)

    private var searchContent: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Apple Podcasts", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runSearchImmediately() }
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            results = []
                            searchError = nil
                            didSearch = false
                            searchTask?.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
            }

            if let searchError {
                Section {
                    Text(searchError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if didSearch && !isSearching && results.isEmpty && searchError == nil {
                Section {
                    ContentUnavailableView(
                        "No podcasts found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or artist, or switch to Feed URL.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { item in
                        ItunesResultRow(
                            result: item,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl },
                            isSubscribing: subscribingFeedUrl == item.feedUrl || (store.isLoading && subscribingFeedUrl == item.feedUrl),
                            onSubscribe: {
                                Task { await subscribeSearchResult(item) }
                            }
                        )
                    }
                }
            }

            if let error = store.lastError, mode == .search {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Feed URL

    private var urlContent: some View {
        Form {
            Section("Feed URL") {
                TextField("https://example.com/feed.xml", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($urlFocused)
            }
            if let error = store.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("Paste an RSS/Atom podcast feed URL, or use Search to find feeds via Apple Podcasts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if mode == .url {
                urlFocused = true
            }
        }
    }

    // MARK: - Actions

    private func scheduleSearch(for term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            searchError = nil
            didSearch = false
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performSearch(term: trimmed)
        }
    }

    private func runSearchImmediately() {
        searchTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask = Task {
            await performSearch(term: trimmed)
        }
    }

    @MainActor
    private func performSearch(term: String) async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let found = try await searcher.search(term: term)
            guard !Task.isCancelled else { return }
            results = found
            didSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            didSearch = true
            searchError = error.localizedDescription
        }
    }

    @MainActor
    private func subscribeSearchResult(_ item: ItunesPodcastResult) async {
        guard !item.feedUrl.isEmpty else { return }
        subscribingFeedUrl = item.feedUrl
        defer { subscribingFeedUrl = nil }
        await store.subscribe(feedUrl: item.feedUrl)
        if store.lastError == nil {
            dismiss()
        }
    }

    @MainActor
    private func subscribeURL() async {
        await store.subscribe(feedUrl: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.lastError == nil {
            dismiss()
        }
    }
}

// MARK: - Result row

private struct ItunesResultRow: View {
    let result: ItunesPodcastResult
    let isSubscribed: Bool
    let isSubscribing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(result.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSubscribed {
                Text("Subscribed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(isSubscribing ? "…" : "Subscribe") {
                    onSubscribe()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSubscribing || result.feedUrl.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 56
        if let url = result.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder
                .frame(width: size, height: size)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
    }
}
