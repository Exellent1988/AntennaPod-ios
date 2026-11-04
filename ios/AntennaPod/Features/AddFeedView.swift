import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Add podcast: Apple Podcasts / Podcast Index / fyyd search + preview-by-URL (confirm subscribe) + Add from Clipboard.
/// URL tab: trim/normalize (https default when scheme missing), validation errors, paste, already-subscribed before Preview.
struct AddFeedView: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .apple
    @State private var urlText = "https://"
    @State private var urlValidationError: String?
    @FocusState private var urlFocused: Bool

    // Apple Podcasts search
    @State private var appleSearchText = ""
    @State private var appleResults: [ItunesPodcastResult] = []
    @State private var appleIsSearching = false
    @State private var appleSearchError: String?
    @State private var appleDidSearch = false
    @State private var appleSearchTask: Task<Void, Never>?

    // Podcast Index search
    @State private var indexSearchText = ""
    @State private var indexResults: [PodcastIndexPodcastResult] = []
    @State private var indexIsSearching = false
    @State private var indexSearchError: String?
    @State private var indexDidSearch = false
    @State private var indexSearchTask: Task<Void, Never>?
    @State private var indexHasKeys = PodcastIndexKeychain.hasCredentials

    // fyyd search
    @State private var fyydSearchText = ""
    @State private var fyydResults: [FyydPodcastResult] = []
    @State private var fyydIsSearching = false
    @State private var fyydSearchError: String?
    @State private var fyydDidSearch = false
    @State private var fyydSearchTask: Task<Void, Never>?

    @State private var previewRequest: FeedPreviewRequest?
    /// Trimmed http(s) URL from the pasteboard when it looks plausible; nil hides the action.
    @State private var clipboardFeedURL: String?
    @Environment(\.scenePhase) private var scenePhase

    // Local folder
    @State private var showFolderPicker = false
    @State private var folderError: String?
    @State private var folderStatus: String?
    @State private var isAddingFolder = false

    // OPML from Files
    @State private var showOpmlImporter = false
    @State private var showOpmlImportResult = false
    @State private var opmlPickError: String?

    private let itunesSearcher = ItunesSearchService()
    private let podcastIndexSearcher = PodcastIndexSearchService()
    private let fyydSearcher = FyydSearchService()
    private let debounceNs: UInt64 = 400_000_000 // 400 ms

    private enum AddMode: String, CaseIterable, Identifiable {
        case apple
        case podcastIndex
        case fyyd
        case url
        case folder
        case opml
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .apple: "Apple"
            case .podcastIndex: "Index"
            case .fyyd: "fyyd"
            case .url: "URL"
            case .folder: "Folder"
            case .opml: "OPML"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(AddMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch mode {
                case .apple:
                    appleSearchContent
                case .podcastIndex:
                    podcastIndexSearchContent
                case .fyyd:
                    fyydSearchContent
                case .url:
                    urlContent
                case .folder:
                    folderContent
                case .opml:
                    opmlContent
                }
            }
            .navigationTitle("Add podcast")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $previewRequest) { request in
                FeedPreviewView(request: request) {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appleSearchTask?.cancel()
                        indexSearchTask?.cancel()
                        fyydSearchTask?.cancel()
                        dismiss()
                    }
                }
                if let clipboardFeedURL {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            addFromClipboard(clipboardFeedURL)
                        } label: {
                            Label("Add from Clipboard", systemImage: "doc.on.clipboard")
                        }
                        .accessibilityLabel(String(localized: "Add from Clipboard"))
                        .accessibilityHint(String(localized: "Opens a preview for the feed URL on the pasteboard"))
                    }
                }
                if mode == .url {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Preview") {
                            openURLPreview()
                        }
                        .disabled(!canPreviewURL)
                        .accessibilityHint(String(localized: "Fetches and previews the feed before subscribe. Does not subscribe until you confirm."))
                    }
                }
            }
            .onChange(of: appleSearchText) { _, newValue in
                scheduleAppleSearch(for: newValue)
            }
            .onChange(of: indexSearchText) { _, newValue in
                scheduleIndexSearch(for: newValue)
            }
            .onChange(of: fyydSearchText) { _, newValue in
                scheduleFyydSearch(for: newValue)
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .podcastIndex {
                    indexHasKeys = PodcastIndexKeychain.hasCredentials
                }
                refreshClipboardFeedURL()
            }
            .onDisappear {
                appleSearchTask?.cancel()
                indexSearchTask?.cancel()
                fyydSearchTask?.cancel()
            }
            .onAppear {
                refreshClipboardFeedURL()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshClipboardFeedURL()
                }
            }
        }
    }

    // MARK: - Search (Apple Podcasts)

    private var appleSearchContent: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search Apple Podcasts", text: $appleSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runAppleSearchImmediately() }
                        .accessibilityLabel(String(localized: "Search Apple Podcasts"))
                        .accessibilityHint(String(localized: "Searches Apple Podcasts. Results open Preview before subscribe."))
                    if appleIsSearching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Searching Apple Podcasts"))
                    } else if !appleSearchText.isEmpty {
                        Button {
                            appleSearchText = ""
                            appleResults = []
                            appleSearchError = nil
                            appleDidSearch = false
                            appleSearchTask?.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Clear search"))
                    }
                }
            }

            if let appleSearchError {
                Section {
                    Text(appleSearchError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(appleSearchError)
                }
            }

            if appleDidSearch && !appleIsSearching && appleResults.isEmpty && appleSearchError == nil {
                Section {
                    ContentUnavailableView(
                        "No podcasts found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or artist, or switch to Index / fyyd / URL.")
                    )
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No podcasts found"))
                    .accessibilityValue(
                        String(localized: "Try another name or artist, or switch to Index / fyyd / URL.")
                    )
                    .accessibilityHint(
                        String(localized: "Change or clear Discover search, or switch to Index, fyyd, or Feed URL.")
                    )
                }
            }

            if !appleResults.isEmpty {
                Section("Results") {
                    ForEach(appleResults) { item in
                        DiscoveryResultRow(
                            title: item.title,
                            author: item.author,
                            artworkURL: item.artworkURL,
                            feedUrl: item.feedUrl,
                            isSubscribed: FeedURLNormalization.subscribedFeed(matching: item.feedUrl, in: store.feeds) != nil,
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
    }

    // MARK: - Search (Podcast Index)

    private var podcastIndexSearchContent: some View {
        List {
            if !indexHasKeys {
                Section {
                    ContentUnavailableView(
                        "API keys required",
                        systemImage: "key",
                        description: Text(
                            "Podcast Index needs a free API key and secret from podcastindex.org (API docs / register). Paste them under Settings → Discovery. Keys stay in the Keychain — nothing is hardcoded or shipped with the app."
                        )
                    )
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text("No directory search without your keys. Use Apple, fyyd, or URL meanwhile. Keys are never shipped with the app.")
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Search Podcast Index", text: $indexSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { runIndexSearchImmediately() }
                            .accessibilityLabel(String(localized: "Search Podcast Index"))
                            .accessibilityHint(String(localized: "Searches podcastindex.org with your Keychain API keys. Results open Preview before subscribe."))
                        if indexIsSearching {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(String(localized: "Searching Podcast Index"))
                        } else if !indexSearchText.isEmpty {
                            Button {
                                indexSearchText = ""
                                indexResults = []
                                indexSearchError = nil
                                indexDidSearch = false
                                indexSearchTask?.cancel()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Clear search"))
                        }
                    }
                } footer: {
                    Text("Uses your Podcast Index API key from Settings → Discovery (Keychain only). Tap a result for Preview → Confirm Subscribe — not fire-and-forget.")
                }

                if let indexSearchError {
                    Section {
                        Text(indexSearchError)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .accessibilityLabel(indexSearchError)
                        Button("Retry search") {
                            runIndexSearchImmediately()
                        }
                        .disabled(indexSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || indexIsSearching)
                        .accessibilityHint(String(localized: "Runs the Podcast Index search again with the same term"))
                    }
                }

                if !indexDidSearch && !indexIsSearching && indexSearchError == nil && indexResults.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Search Podcast Index",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text("Type a podcast name or author. Results use podcastindex.org — not Apple charts. Subscribe still previews the feed URL.")
                        )
                        .listRowBackground(Color.clear)
                        .accessibilityElement(children: .combine)
                    }
                }

                if indexDidSearch && !indexIsSearching && indexResults.isEmpty && indexSearchError == nil {
                    Section {
                        ContentUnavailableView(
                            "No podcasts found",
                            systemImage: "magnifyingglass",
                            description: Text("Try another name or author, or switch to Apple / fyyd / URL.")
                        )
                        .listRowBackground(Color.clear)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "No podcasts found"))
                        .accessibilityValue(
                            String(localized: "Try another name or author, or switch to Apple / fyyd / URL.")
                        )
                        .accessibilityHint(
                            String(localized: "Change or clear Discover search, or switch to Apple, fyyd, or Feed URL.")
                        )
                    }
                }

                if !indexResults.isEmpty {
                    Section {
                        ForEach(indexResults) { item in
                            DiscoveryResultRow(
                                title: item.title,
                                author: item.author,
                                artworkURL: item.artworkURL,
                                feedUrl: item.feedUrl,
                                isSubscribed: FeedURLNormalization.subscribedFeed(matching: item.feedUrl, in: store.feeds) != nil,
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
                    } header: {
                        Text("Results")
                    } footer: {
                        Text("Showing up to 25 matches with a feed URL. Empty feed URLs are skipped.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            indexHasKeys = PodcastIndexKeychain.hasCredentials
        }
    }

    // MARK: - Feed URL

    private var urlContent: some View {
        Form {
            Section {
                TextField("https://example.com/feed.xml", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($urlFocused)
                    .submitLabel(.go)
                    .onSubmit { openURLPreview() }
                    .accessibilityLabel(String(localized: "Feed URL"))
                    .accessibilityHint(String(localized: "Paste an RSS or Atom podcast feed URL. Missing https is added when the host looks valid."))
                    .onChange(of: urlText) { _, _ in
                        urlValidationError = nil
                    }
                if let urlValidationError {
                    Text(urlValidationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel(urlValidationError)
                }
            } header: {
                Text("Feed URL")
            } footer: {
                Text("Paste an RSS/Atom podcast feed URL. Spaces are trimmed; https:// is added when the scheme is missing and the host looks valid. Preview fetches the feed before you confirm subscribe — same path as discovery.")
            }

            if let match = alreadySubscribedMatch(for: urlText) {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Already subscribed")
                                .font(.subheadline.weight(.semibold))
                            Text(match.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Already subscribed") + ", " + match.title)

                    Button {
                        openAlreadySubscribedPreview(match)
                    } label: {
                        Label("Open feed", systemImage: "arrow.right.circle")
                    }
                    .accessibilityHint(String(localized: "Opens the existing subscription instead of subscribing again"))
                } footer: {
                    Text("This URL matches a podcast already in your library. Open it instead of creating a duplicate.")
                }
            }

            Section {
                Button {
                    pasteURLFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(UIPasteboard.general.string == nil)
                .accessibilityLabel(String(localized: "Paste"))
                .accessibilityHint(String(localized: "Pastes the pasteboard text into the Feed URL field. Does not subscribe."))

                if let clipboardFeedURL {
                    Button {
                        addFromClipboard(clipboardFeedURL)
                    } label: {
                        Label("Add from Clipboard", systemImage: "doc.on.clipboard.fill")
                    }
                    .accessibilityHint(String(localized: "Opens a preview for the feed URL on the pasteboard"))
                    Text(clipboardFeedURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(String(localized: "Clipboard feed URL"))
                }
            } footer: {
                Text("Paste fills the field only. Add from Clipboard opens Preview when the pasteboard holds a usable http(s) feed URL — does not subscribe until you confirm.")
            }

            Section {
                Button("Preview feed") {
                    openURLPreview()
                }
                .disabled(!canPreviewURL)
                .accessibilityHint(String(localized: "Fetches and previews the feed before subscribe. Does not subscribe until you confirm."))
            }
        }
        .onAppear {
            refreshClipboardFeedURL()
            if mode == .url {
                urlFocused = true
            }
        }
    }

    // MARK: - Local folder

    private var folderContent: some View {
        List {
            Section {
                Button {
                    folderError = nil
                    folderStatus = nil
                    showFolderPicker = true
                } label: {
                    Label("Choose folder…", systemImage: "folder.badge.plus")
                }
                .disabled(isAddingFolder)
                .accessibilityLabel(String(localized: "Choose folder…"))
                .accessibilityHint(String(localized: "Opens Files to pick a folder of audio files. Creates a local subscription — no RSS and no network."))

                if isAddingFolder {
                    ProgressView("Scanning folder…")
                        .accessibilityLabel(String(localized: "Scanning folder…"))
                }
                if let folderStatus {
                    Text(folderStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(folderStatus)
                }
                if let folderError {
                    Text(folderError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel(folderError)
                }
            } header: {
                Text("Local folder feed")
            } footer: {
                Text("Beta: pick a folder of audio files (\(LocalFolderFeed.audioFormatsDisplay)). Creates a synthetic subscription from files in that folder only (not subfolders) — no RSS, no network refresh, no Podcasting 2.0 / iTunes tags. Access is kept via a security-scoped bookmark; unsubscribe releases it. Refresh / Rescan re-reads the folder. Local folder podcasts are omitted from OPML, HTML export, and gpodder sync.")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What you get")
                            .font(.subheadline.weight(.semibold))
                        Text("Episodes = audio files in the folder. Play works offline from the file path. Empty folders are allowed — add files later, then Rescan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What you do not get")
                            .font(.subheadline.weight(.semibold))
                        Text("No RSS / Atom feed, no Podcasting 2.0 chapters or funding tags from the folder, no automatic network updates, no OPML export of this subscription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Honesty")
            }
        }
        .listStyle(.insetGrouped)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderPick(result)
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            // User cancel typically does not report failure; surface real picker/permission errors.
            folderError = error.localizedDescription
            folderStatus = nil
        case .success(let urls):
            guard let url = urls.first else {
                folderError = String(localized: "No folder was selected.")
                return
            }
            isAddingFolder = true
            folderError = nil
            folderStatus = nil
            defer { isAddingFolder = false }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                if let existing = LocalFolderBookmarkStore.existingFeed(matchingFolderURL: url, in: store.feeds) {
                    folderError = String(localized: "This folder is already added as “\(existing.title)”. Open it from Subscriptions instead of adding a duplicate.")
                    return
                }
                let feed = try store.subscribeLocalFolder(folderURL: url)
                let count = feed.episodes.count
                if count == 0 {
                    folderStatus = String(localized: "Added “\(url.lastPathComponent)” with no audio files yet. Add \(LocalFolderFeed.audioFormatsDisplay) files, then Rescan from the feed or swipe Refresh on Subscriptions.")
                } else if count == 1 {
                    folderStatus = String(localized: "Added “\(url.lastPathComponent)” as a local folder feed (1 episode).")
                } else {
                    folderStatus = String(localized: "Added “\(url.lastPathComponent)” as a local folder feed (\(count) episodes).")
                }
                dismiss()
            } catch {
                folderError = error.localizedDescription
            }
        }
    }

    // MARK: - OPML from Files

    private var opmlContent: some View {
        List {
            Section {
                Button {
                    opmlPickError = nil
                    showOpmlImporter = true
                } label: {
                    Label("Choose OPML file…", systemImage: "doc.badge.arrow.up")
                }
                .disabled(store.opmlImport.isImporting)
                .accessibilityLabel(String(localized: "Choose OPML file…"))
                .accessibilityHint(String(localized: "Opens Files to pick an .opml or .xml subscription list. Already subscribed feeds are skipped; each new feed is fetched over the network."))

                if store.opmlImport.isImporting {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: store.opmlImport.fraction)
                        Text(opmlProgressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "OPML import in progress"))
                    .accessibilityValue(opmlProgressLabel)
                } else if store.opmlImport.total > 0 {
                    Button {
                        showOpmlImportResult = true
                    } label: {
                        Text(store.opmlImport.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(store.opmlImport.summary)
                    .accessibilityHint(String(localized: "Shows added, already subscribed, and failed counts from the last OPML import."))
                }

                if let opmlPickError {
                    Text(opmlPickError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let err = store.opmlImportError, !store.opmlImport.isImporting {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Import from Files")
            } footer: {
                Text("Beta: pick an .opml or .xml subscription list from Files. Already subscribed feed URLs are skipped. Each new feed is fetched over the network. Same import path as Settings → Import / Export. No cloud sync.")
                    .accessibilityLabel(String(localized: "Beta: pick an .opml or .xml subscription list from Files. Already subscribed feed URLs are skipped. Each new feed is fetched over the network. Same import path as Settings → Import / Export. No cloud sync."))
            }
        }
        .listStyle(.insetGrouped)
        .fileImporter(
            isPresented: $showOpmlImporter,
            allowedContentTypes: [.opml, .xml, .data],
            allowsMultipleSelection: false
        ) { result in
            handleOpmlPick(result)
        }
        .sheet(isPresented: $showOpmlImportResult) {
            OpmlImportResultView()
        }
        .onChange(of: store.opmlImport.isImporting) { _, importing in
            if !importing, store.opmlImport.total > 0, mode == .opml {
                showOpmlImportResult = true
            }
        }
    }

    private var opmlProgressLabel: String {
        let s = store.opmlImport
        let base = "\(s.completed)/\(s.total)"
        if let title = s.currentTitle {
            return "\(base) — \(title)"
        }
        return base
    }

    private func handleOpmlPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            opmlPickError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            opmlPickError = nil
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let data = try Data(contentsOf: url)
                    await store.importOpml(data: data, sourceFileName: url.lastPathComponent)
                } catch {
                    opmlPickError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Apple search actions

    private func scheduleAppleSearch(for term: String) {
        appleSearchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appleResults = []
            appleSearchError = nil
            appleDidSearch = false
            appleIsSearching = false
            return
        }
        appleSearchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performAppleSearch(term: trimmed)
        }
    }

    private func runAppleSearchImmediately() {
        appleSearchTask?.cancel()
        let trimmed = appleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appleSearchTask = Task {
            await performAppleSearch(term: trimmed)
        }
    }

    @MainActor
    private func performAppleSearch(term: String) async {
        appleIsSearching = true
        appleSearchError = nil
        defer { appleIsSearching = false }
        do {
            let found = try await itunesSearcher.search(term: term)
            guard !Task.isCancelled else { return }
            appleResults = found
            appleDidSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            appleResults = []
            appleDidSearch = true
            appleSearchError = error.localizedDescription
        }
    }

    // MARK: - Podcast Index search actions

    private func scheduleIndexSearch(for term: String) {
        indexSearchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            indexResults = []
            indexSearchError = nil
            indexDidSearch = false
            indexIsSearching = false
            return
        }
        guard indexHasKeys else { return }
        indexSearchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performIndexSearch(term: trimmed)
        }
    }

    private func runIndexSearchImmediately() {
        indexSearchTask?.cancel()
        let trimmed = indexSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, indexHasKeys else { return }
        indexSearchTask = Task {
            await performIndexSearch(term: trimmed)
        }
    }

    @MainActor
    private func performIndexSearch(term: String) async {
        indexIsSearching = true
        indexSearchError = nil
        defer { indexIsSearching = false }
        do {
            let found = try await podcastIndexSearcher.search(term: term)
            guard !Task.isCancelled else { return }
            indexResults = found
            indexDidSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            indexResults = []
            indexDidSearch = true
            indexSearchError = error.localizedDescription
        }
    }

    // MARK: - Search (fyyd)

    private var fyydSearchContent: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search fyyd", text: $fyydSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runFyydSearchImmediately() }
                        .accessibilityLabel(String(localized: "Search fyyd"))
                        .accessibilityHint(String(localized: "Searches fyyd. Results open Preview before subscribe."))
                    if fyydIsSearching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Searching fyyd"))
                    } else if !fyydSearchText.isEmpty {
                        Button {
                            fyydSearchText = ""
                            fyydResults = []
                            fyydSearchError = nil
                            fyydDidSearch = false
                            fyydSearchTask?.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Clear search"))
                    }
                }
            }

            Section {
                Text("fyyd.de podcast directory — no API key required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let fyydSearchError {
                Section {
                    Text(fyydSearchError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(fyydSearchError)
                }
            }

            if fyydDidSearch && !fyydIsSearching && fyydResults.isEmpty && fyydSearchError == nil {
                Section {
                    ContentUnavailableView(
                        "No podcasts found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or author, or switch to Apple / Index / URL.")
                    )
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No podcasts found"))
                    .accessibilityValue(
                        String(localized: "Try another name or author, or switch to Apple / Index / URL.")
                    )
                    .accessibilityHint(
                        String(localized: "Change or clear Discover search, or switch to Apple, Index, or Feed URL.")
                    )
                }
            }

            if !fyydResults.isEmpty {
                Section("Results") {
                    ForEach(fyydResults) { item in
                        DiscoveryResultRow(
                            title: item.title,
                            author: item.author,
                            artworkURL: item.artworkURL,
                            feedUrl: item.feedUrl,
                            isSubscribed: FeedURLNormalization.subscribedFeed(matching: item.feedUrl, in: store.feeds) != nil,
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
    }

    // MARK: - fyyd search actions

    private func scheduleFyydSearch(for term: String) {
        fyydSearchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fyydResults = []
            fyydSearchError = nil
            fyydDidSearch = false
            fyydIsSearching = false
            return
        }
        fyydSearchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performFyydSearch(term: trimmed)
        }
    }

    private func runFyydSearchImmediately() {
        fyydSearchTask?.cancel()
        let trimmed = fyydSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fyydSearchTask = Task {
            await performFyydSearch(term: trimmed)
        }
    }

    @MainActor
    private func performFyydSearch(term: String) async {
        fyydIsSearching = true
        fyydSearchError = nil
        defer { fyydIsSearching = false }
        do {
            let found = try await fyydSearcher.search(term: term)
            guard !Task.isCancelled else { return }
            fyydResults = found
            fyydDidSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            fyydResults = []
            fyydDidSearch = true
            fyydSearchError = error.localizedDescription
        }
    }

    // MARK: - Clipboard

    /// Refresh pasteboard detection. Only http/https with a host after normalization; first line only.
    /// Does **not** auto-subscribe — the action stays user-initiated.
    private func refreshClipboardFeedURL() {
        clipboardFeedURL = Self.plausibleFeedURL(from: UIPasteboard.general.string)
    }

    /// True when the string looks like a network feed URL the existing Preview path can try.
    /// Accepts scheme-less host/path (normalizes to https://) the same way as the URL field.
    static func plausibleFeedURL(from pasteboardString: String?) -> String? {
        guard let raw = pasteboardString else { return nil }
        if case .ok(let url) = FeedURLNormalization.normalize(raw) {
            return url
        }
        return nil
    }

    /// Paste pasteboard text into the URL field only (no Preview / no subscribe).
    private func pasteURLFromClipboard() {
        guard let raw = UIPasteboard.general.string else {
            urlValidationError = String(localized: "Clipboard is empty")
            return
        }
        mode = .url
        switch FeedURLNormalization.normalize(raw) {
        case .ok(let url):
            urlText = url
            urlValidationError = nil
            refreshClipboardFeedURL()
        case .empty:
            urlValidationError = String(localized: "Clipboard is empty")
        case .invalid:
            // Still paste raw trimmed first line so the user can edit; show validation.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? trimmed
            urlText = first
            urlValidationError = String(localized: "Enter a valid http(s) feed URL")
            refreshClipboardFeedURL()
        }
    }

    /// Fill the URL field and open the same Preview → Confirm Subscribe path as manual URL entry.
    private func addFromClipboard(_ feedURL: String) {
        switch FeedURLNormalization.normalize(feedURL) {
        case .ok(let url):
            mode = .url
            urlText = url
            urlValidationError = nil
            previewRequest = FeedPreviewRequest(feedUrl: url)
        case .empty, .invalid:
            refreshClipboardFeedURL()
            urlValidationError = String(localized: "Enter a valid http(s) feed URL")
        }
    }

    // MARK: - Preview

    private var canPreviewURL: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed != "https://" && trimmed != "http://"
    }

    private func alreadySubscribedMatch(for raw: String) -> PodcastFeed? {
        switch FeedURLNormalization.normalize(raw) {
        case .ok(let url):
            return FeedURLNormalization.subscribedFeed(matching: url, in: store.feeds)
        case .empty, .invalid:
            return nil
        }
    }

    private func openAlreadySubscribedPreview(_ feed: PodcastFeed) {
        urlValidationError = nil
        previewRequest = FeedPreviewRequest(
            feedUrl: feed.feedUrl,
            hintTitle: feed.title,
            hintAuthor: feed.displayAuthor,
            hintArtworkURL: feed.preferredDisplayArtworkURL.flatMap { URL(string: $0) }
                ?? feed.imageUrl.flatMap { URL(string: $0) }
        )
    }

    private func openURLPreview() {
        urlValidationError = nil
        switch FeedURLNormalization.normalize(urlText) {
        case .ok(let url):
            urlText = url
            previewRequest = FeedPreviewRequest(feedUrl: url)
        case .empty:
            urlValidationError = String(localized: "Enter a valid http(s) feed URL")
        case .invalid:
            urlValidationError = String(localized: "Enter a valid http(s) feed URL")
        }
    }
}
