import SwiftUI
import UIKit

/// Scrollable podcast / feed description sheet (plain text; HTML stripped for beta).
/// Parallel to `EpisodeDescriptionSheetView` shownotes. Uses `PodcastFeed.descriptionText`
/// plus optional `author` / `language` / `categories` / `people` / `locations` / `socialInteract` / `value` / `liveItem` / `txt` / `podroll` / `publisher` under the title when the feed provided them (hidden when missing).
/// Supports `.searchable` filter over already-loaded plain paragraphs/lines (case-insensitive,
/// ~250 ms debounce). Does not fetch remote HTML beyond the feed's description field —
/// no WebView / rich HTML renderer.
struct FeedDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let feed: PodcastFeed
    /// Local nickname when set; defaults to RSS `feed.title`.
    var displayTitle: String? = nil

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var resolvedTitle: String {
        let trimmed = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? feed.title : trimmed
    }

    private var plainDescription: String {
        guard let raw = feed.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var hasPlainDescription: Bool {
        !plainDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Full plain podcast description with a title header for system sharing.
    /// This intentionally ignores the searchable, visible subset.
    private var descriptionShareText: String {
        let body = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        let title = resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = title.isEmpty ? String(localized: "Description") : title
        return "\(header)\n\n\(body)"
    }

    private var descriptionShareSubject: String {
        let title = resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Description") : title
    }

    private var displayAuthor: String? {
        feed.displayAuthor
    }

    private var displayLanguage: String? {
        feed.displayLanguage
    }

    private var displayMedium: String? {
        feed.displayMedium
    }

    private var displayItunesType: String? {
        feed.displayItunesType
    }

    private var displayUpdateFrequency: PodcastUpdateFrequency? {
        feed.displayUpdateFrequency
    }

    private var displayItunesCompleteShareText: String {
        feed.itunesCompleteShareText
    }

    private var displayExplicitShareText: String {
        String(localized: "Explicit")
    }

    private var displayBlockedShareText: String {
        feed.podcastBlockAccessibilityLabel
    }

    private var displayCategories: [String] {
        feed.displayCategories
    }

    /// Same feed-provided category list used by Copy, Share, and the combined VoiceOver label.
    private var displayCategoriesShareText: String {
        displayCategories.joined(separator: " · ")
    }

    /// Channel podcast:person when the feed provided them — empty → hide (never invent).
    private var displayPeople: [PodcastPerson] {
        feed.displayPeople
    }

    private var hasPeople: Bool {
        !displayPeople.isEmpty
    }

    /// Channel podcast:location when the feed provided them — empty → hide (never invent / never geocode).
    private var displayLocations: [PodcastLocation] {
        feed.displayLocations
    }

    private var hasLocations: Bool {
        !displayLocations.isEmpty
    }

    /// Channel podcast:socialInteract when the feed provided openable http(s) — empty → hide (never invent).
    private var displaySocialInteracts: [PodcastSocialInteract] {
        feed.displaySocialInteracts
    }

    private var hasSocialInteracts: Bool {
        !displaySocialInteracts.isEmpty
    }

    /// Channel podcast:value when the feed provided recipients — empty → hide (display-only; no payments).
    private var displayValues: [PodcastValue] {
        feed.values
    }

    private var hasValues: Bool {
        !feed.displayValueRecipients.isEmpty
    }

    /// Channel podcast:liveItem when the feed provided them — empty → hide (display-only; no live player).
    private var displayLiveItems: [PodcastLiveItem] {
        feed.displayLiveItems
    }

    private var hasLiveItems: Bool {
        !displayLiveItems.isEmpty
    }

    /// Channel podcast:txt when the feed provided them — empty → hide (display-only Copy / Share / Open).
    private var displayTexts: [PodcastTxt] {
        feed.displayTexts
    }

    private var hasTexts: Bool {
        !displayTexts.isEmpty
    }

    /// Channel podcast:license when the feed provided them — empty → hide (display-only; no DRM).
    private var displayLicenses: [PodcastLicense] {
        feed.displayLicenses
    }

    private var hasLicenses: Bool {
        !displayLicenses.isEmpty
    }

    /// Channel podcast:images / podcast:image when the feed provided variants — empty → hide.
    private var displayImages: [PodcastImageVariant] {
        feed.displayImages
    }

    private var hasImages: Bool {
        !displayImages.isEmpty
    }

    /// Channel podcast:podroll when the feed provided remoteItems — empty → hide (never invent).
    private var displayPodrollItems: [PodcastRemoteItem] {
        feed.displayPodrollItems
    }

    private var hasPodroll: Bool {
        !displayPodrollItems.isEmpty
    }

    /// Channel podcast:publisher when the feed provided remoteItems — empty → hide (never invent).
    private var displayPublisherItems: [PodcastRemoteItem] {
        feed.displayPublisherItems
    }

    private var hasPublisher: Bool {
        !displayPublisherItems.isEmpty
    }

    /// Paragraphs (blank-line split) or non-empty lines when the text is a single block.
    private var paragraphs: [String] {
        let trimmed = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let blankSplit = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if blankSplit.count > 1 { return blankSplit }
        let lineSplit = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lineSplit.isEmpty ? [trimmed] : lineSplit
    }

    /// Visible paragraphs after light-debounced case-insensitive filter.
    private var filteredParagraphs: [String] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return paragraphs }
        return paragraphs.filter { $0.localizedSearchContains(q) }
    }

    private var isFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var websiteURL: URL? {
        feed.websiteURL
    }

    /// Channel claim badges shown on the description sheet, matching Feed detail.
    /// Locked is a display-only transfer claim; neither claim changes subscribe/play behavior.
    @ViewBuilder
    private var feedClaimMetadata: some View {
        if feed.isExplicit {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Explicit"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(String(localized: "Explicit"))
                explicitActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if feed.isLocked {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Locked"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                    Text(String(localized: "This feed claims to be locked for transfer. This app does not verify ownership."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    [
                        String(localized: "Locked"),
                        String(localized: "This feed claims to be locked for transfer. This app does not verify ownership.")
                    ].joined(separator: ". ")
                )

                if let owner = feed.displayLockedOwner {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Locked owner \(owner)"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityLabel(String(localized: "Locked owner \(owner)"))
                        HStack(spacing: 12) {
                            Button {
                                copyLockedOwner(owner)
                            } label: {
                                Label("Copy locked owner", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy locked owner"))
                            .accessibilityHint(String(localized: "Copies the feed-provided locked owner string to the pasteboard; display-only; no ownership verification"))

                            if let url = lockedOwnerShareURL(owner) {
                                ShareLink(
                                    item: url,
                                    subject: Text(resolvedTitle)
                                ) {
                                    Label("Share locked owner", systemImage: "square.and.arrow.up")
                                        .font(.subheadline)
                                }
                                .accessibilityLabel(String(localized: "Share locked owner"))
                                .accessibilityHint(String(localized: "Shares the feed-provided locked owner string; display-only; no ownership verification"))
                            } else {
                                ShareLink(
                                    item: owner,
                                    subject: Text(resolvedTitle)
                                ) {
                                    Label("Share locked owner", systemImage: "square.and.arrow.up")
                                        .font(.subheadline)
                                }
                                .accessibilityLabel(String(localized: "Share locked owner"))
                                .accessibilityHint(String(localized: "Shares the feed-provided locked owner string; display-only; no ownership verification"))
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if feed.isBlocked {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Blocked"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                    Text(String(localized: "This feed marks podcast:block or itunes:block for directories. This app does not enforce it — subscribe and play still work."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(feed.podcastBlockAccessibilityLabel)
                blockedActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var feedTypeMetadata: some View {
        if let medium = displayMedium {
            VStack(alignment: .leading, spacing: 8) {
                Text(medium)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(String(localized: "Medium \(medium)"))
                mediumActions(medium)
            }
        }

        if let itunesType = displayItunesType {
            VStack(alignment: .leading, spacing: 8) {
                Text(itunesType)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(feed.itunesTypeAccessibilityLabel ?? itunesType)
                itunesTypeActions(itunesType)
                if feed.isItunesTypeSerial {
                    Text(String(localized: "Serial podcasts may use Oldest first once for narrative order when per-feed sort is unset. You can still pick any sort. The itunes:type capsule stays display-only."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Serial podcasts may use Oldest first once for narrative order when per-feed sort is unset. You can still pick any sort. The itunes:type capsule stays display-only."))
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty && displayMedium == nil && displayItunesType == nil && !feed.isExplicit && !feed.isLocked && !feed.isBlocked && !hasPeople && !hasLocations && !hasSocialInteracts && !hasValues && !hasLiveItems && !hasTexts && !hasLicenses {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "info.circle",
                        description: Text("This podcast has no description in the feed.")
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "No description"))
                    .accessibilityValue(String(localized: "This podcast has no description in the feed."))
                    .accessibilityHint(String(localized: "There is no podcast description to read."))
                } else if plainDescription.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            feedClaimMetadata
                            feedTypeMetadata

                            if hasPeople {
                                PodcastPeopleListView(people: displayPeople)
                            }
                            if hasLocations {
                                PodcastLocationsListView(locations: displayLocations)
                            }
                            if hasSocialInteracts {
                                PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                            }
                            if hasValues {
                                PodcastValueRecipientsListView(values: displayValues)
                            }
                            if hasLiveItems {
                                PodcastLiveItemsListView(liveItems: displayLiveItems)
                            }
                            if hasTexts {
                                PodcastTxtListView(texts: displayTexts)
                            }
                            if hasLicenses {
                                PodcastLicenseListView(licenses: displayLicenses)
                            }
                            if hasImages {
                                PodcastImagesListView(images: displayImages)
                            }
                            if hasPodroll {
                                PodcastPodrollListView(items: displayPodrollItems)
                            }
                            if hasPublisher {
                                PodcastPublisherListView(items: displayPublisherItems)
                            }
                        }
                        .padding()
                    }
                } else {
                    descriptionContent
                        .searchable(text: $searchText, prompt: "Search description")
                        .onChange(of: searchText) { _, newValue in
                            scheduleFilter(for: newValue)
                        }
                }
            }
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyPodcastDescription()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!hasPlainDescription)
                    .accessibilityLabel(String(localized: "Copy podcast description"))
                    .accessibilityHint(String(localized: "Copies the full podcast description to the pasteboard as plain text, with HTML stripped; ignores search filters"))

                    ShareLink(
                        item: descriptionShareText,
                        subject: Text(descriptionShareSubject)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!hasPlainDescription)
                    .accessibilityLabel(String(localized: "Share podcast description"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the full podcast description as plain text, with HTML stripped; ignores search filters")
                    )

                    if let url = websiteURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(String(localized: "Open podcast website"))
                        .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Plain text — HTML tags stripped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
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
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if isFiltering && filteredParagraphs.isEmpty {
            ContentUnavailableView(
                "No matching text",
                systemImage: "magnifyingglass",
                description: Text("No description text matches your search.")
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "No matching text"))
            .accessibilityValue(String(localized: "No description text matches your search."))
            .accessibilityHint(String(localized: "Change or clear the podcast description search to see other text."))
        } else if isFiltering {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(resolvedTitle)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    if let podcastTitle = EpisodeCopyLinks.trimmedFeedTitle(resolvedTitle) {
                        podcastTitleActions(podcastTitle)
                    }

                    if let author = displayAuthor {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(String(localized: "Author \(author)"))
                            authorActions(author)
                        }
                    }

                    if let language = displayLanguage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(String(localized: "Language \(language)"))
                            languageActions(language)
                        }
                    }

                    feedTypeMetadata

                    if let uf = displayUpdateFrequency {
                        VStack(alignment: .leading, spacing: 8) {
                            FeedUpdateFrequencyDetailBlock(frequency: uf)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            updateFrequencyActions(uf)
                        }
                    }

                    if feed.isItunesComplete {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Complete"))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2), in: Capsule())
                                Text(String(localized: "This podcast marks itunes:complete. The publisher claims no further episodes. This does not change Keep updated or refresh."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(feed.itunesCompleteAccessibilityLabel)
                            itunesCompleteActions
                        }
                    }

                    feedClaimMetadata

                    if !displayCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            FeedDescriptionCategoryChips(categories: displayCategories)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    String(localized: "Categories \(displayCategoriesShareText)")
                                )
                            categoryActions
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .contain)
                    }

                    if hasPeople {
                        PodcastPeopleListView(people: displayPeople)
                    }

                    if hasLocations {
                        PodcastLocationsListView(locations: displayLocations)
                    }
                    if hasSocialInteracts {
                        PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                    }
                    if hasValues {
                        PodcastValueRecipientsListView(values: displayValues)
                    }
                    if hasLiveItems {
                        PodcastLiveItemsListView(liveItems: displayLiveItems)
                    }
                    if hasTexts {
                        PodcastTxtListView(texts: displayTexts)
                    }
                    if hasLicenses {
                        PodcastLicenseListView(licenses: displayLicenses)
                    }
                    if hasImages {
                        PodcastImagesListView(images: displayImages)
                    }
                    if hasPodroll {
                        PodcastPodrollListView(items: displayPodrollItems)
                    }
                    if hasPublisher {
                        PodcastPublisherListView(items: displayPublisherItems)
                    }

                    ForEach(Array(filteredParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityLabel(paragraph)
                    }
                }
                .padding()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(resolvedTitle)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    if let podcastTitle = EpisodeCopyLinks.trimmedFeedTitle(resolvedTitle) {
                        podcastTitleActions(podcastTitle)
                    }

                    if let author = displayAuthor {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(String(localized: "Author \(author)"))
                            authorActions(author)
                        }
                    }

                    if let language = displayLanguage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(String(localized: "Language \(language)"))
                            languageActions(language)
                        }
                    }

                    feedTypeMetadata

                    if let uf = displayUpdateFrequency {
                        VStack(alignment: .leading, spacing: 8) {
                            FeedUpdateFrequencyDetailBlock(frequency: uf)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            updateFrequencyActions(uf)
                        }
                    }

                    if feed.isItunesComplete {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Complete"))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2), in: Capsule())
                                Text(String(localized: "This podcast marks itunes:complete. The publisher claims no further episodes. This does not change Keep updated or refresh."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(feed.itunesCompleteAccessibilityLabel)
                            itunesCompleteActions
                        }
                    }

                    feedClaimMetadata

                    if !displayCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            FeedDescriptionCategoryChips(categories: displayCategories)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    String(localized: "Categories \(displayCategoriesShareText)")
                                )
                            categoryActions
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .contain)
                    }

                    if hasPeople {
                        PodcastPeopleListView(people: displayPeople)
                    }

                    if hasLocations {
                        PodcastLocationsListView(locations: displayLocations)
                    }
                    if hasSocialInteracts {
                        PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                    }
                    if hasValues {
                        PodcastValueRecipientsListView(values: displayValues)
                    }
                    if hasLiveItems {
                        PodcastLiveItemsListView(liveItems: displayLiveItems)
                    }
                    if hasTexts {
                        PodcastTxtListView(texts: displayTexts)
                    }
                    if hasLicenses {
                        PodcastLicenseListView(licenses: displayLicenses)
                    }
                    if hasImages {
                        PodcastImagesListView(images: displayImages)
                    }
                    if hasPodroll {
                        PodcastPodrollListView(items: displayPodrollItems)
                    }
                    if hasPublisher {
                        PodcastPublisherListView(items: displayPublisherItems)
                    }

                    Text(plainDescription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func podcastTitleActions(_ title: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyPodcastTitle(title)
            } label: {
                Label("Copy podcast title", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy podcast title"))
            .accessibilityHint(String(localized: "Copies the trimmed podcast display title to the pasteboard; hidden when the title is empty; no title invented"))

            ShareLink(item: title, subject: Text(title)) {
                Label("Share podcast title", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share podcast title"))
            .accessibilityHint(String(localized: "Shares the trimmed podcast display title as plain text; hidden when the title is empty; no title invented"))
        }
    }

    private func copyPodcastTitle(_ title: String) {
        guard let trimmed = EpisodeCopyLinks.trimmedFeedTitle(title) else { return }
        copiedAlertMessage = EpisodeCopyLinks.copyPodcastTitle(trimmed)
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func authorActions(_ author: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyAuthor(author)
            } label: {
                Label("Copy author", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy author"))
            .accessibilityHint(
                String(localized: "Copies the feed-provided author string to the pasteboard; display-only; no profile URL")
            )

            ShareLink(
                item: author,
                subject: Text(resolvedTitle)
            ) {
                Label("Share author", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share author"))
            .accessibilityHint(
                String(localized: "Shares the same feed-provided author string as plain text; no profile URL")
            )
        }
    }

    private func copyAuthor(_ author: String) {
        UIPasteboard.general.string = author
        copiedAlertMessage = String(localized: "Podcast author copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private func languageActions(_ language: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyLanguage(language)
            } label: {
                Label("Copy language", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy language"))
            .accessibilityHint(
                String(localized: "Copies the same feed-provided language string shown above to the pasteboard; display-only; no code invented")
            )

            ShareLink(
                item: language,
                subject: Text(resolvedTitle)
            ) {
                Label("Share language", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share language"))
            .accessibilityHint(
                String(localized: "Shares the same feed-provided language string shown above as plain text; display-only; no code invented")
            )
        }
    }

    private func copyLanguage(_ language: String) {
        UIPasteboard.general.string = language
        copiedAlertMessage = String(localized: "Podcast language copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private func updateFrequencyActions(_ frequency: PodcastUpdateFrequency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = frequency.shareText {
                HStack(spacing: 12) {
                    Button {
                        copyUpdateFrequency(text)
                    } label: {
                        Label("Copy update frequency", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy update frequency"))
                    .accessibilityHint(
                        String(localized: "Copies the same feed-provided update-frequency summary shown above to the pasteboard; display-only; does not change Keep updated or refresh")
                    )

                    ShareLink(
                        item: text,
                        subject: Text(resolvedTitle)
                    ) {
                        Label("Share update frequency", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share update frequency"))
                    .accessibilityHint(
                        String(localized: "Shares the same feed-provided update-frequency summary shown above as plain text; display-only; does not change Keep updated or refresh")
                    )
                }
            }

            // Distinct from combined update-frequency summary — exact Recurrence caption only; hide when rrule missing.
            if let caption = frequency.displayRruleCaption {
                HStack(spacing: 12) {
                    Button {
                        copyUpdateFrequencyRrule(caption)
                    } label: {
                        Label("Copy recurrence", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy recurrence"))
                    .accessibilityHint(
                        String(localized: "Copies the same Recurrence caption shown above to the pasteboard; display-only; does not change Keep updated or refresh")
                    )

                    ShareLink(
                        item: caption,
                        subject: Text(resolvedTitle)
                    ) {
                        Label("Share recurrence", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share recurrence"))
                    .accessibilityHint(
                        String(localized: "Shares the same Recurrence caption shown above as plain text; display-only; does not change Keep updated or refresh")
                    )
                }
            }

            // Distinct from combined update-frequency summary — exact Starts caption only; hide when dtstart missing.
            if let caption = frequency.displayDtstartCaption {
                HStack(spacing: 12) {
                    Button {
                        copyUpdateFrequencyDtstart(caption)
                    } label: {
                        Label("Copy start timestamp", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy start timestamp"))
                    .accessibilityHint(
                        String(localized: "Copies the same Starts caption shown above to the pasteboard; display-only; does not change Keep updated or refresh")
                    )

                    ShareLink(
                        item: caption,
                        subject: Text(resolvedTitle)
                    ) {
                        Label("Share start timestamp", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share start timestamp"))
                    .accessibilityHint(
                        String(localized: "Shares the same Starts caption shown above as plain text; display-only; does not change Keep updated or refresh")
                    )
                }
            }
        }
    }

    private func copyUpdateFrequency(_ text: String) {
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Update frequency copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyUpdateFrequencyRrule(_ caption: String) {
        UIPasteboard.general.string = caption
        copiedAlertMessage = String(localized: "Recurrence copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyUpdateFrequencyDtstart(_ caption: String) {
        UIPasteboard.general.string = caption
        copiedAlertMessage = String(localized: "Start timestamp copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private var itunesCompleteActions: some View {
        HStack(spacing: 12) {
            Button {
                copyItunesComplete()
            } label: {
                Label("Copy complete claim", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy complete claim"))
            .accessibilityHint(
                String(localized: "Copies the localized Complete claim and its feed-provided itunes:complete footnote to the pasteboard; display-only; does not change Keep updated or refresh")
            )

            ShareLink(
                item: displayItunesCompleteShareText,
                subject: Text(resolvedTitle)
            ) {
                Label("Share complete claim", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share complete claim"))
            .accessibilityHint(
                String(localized: "Shares the localized Complete claim and its feed-provided itunes:complete footnote as plain text; display-only; does not change Keep updated or refresh")
            )
        }
    }

    private func copyItunesComplete() {
        UIPasteboard.general.string = displayItunesCompleteShareText
        copiedAlertMessage = String(localized: "Complete claim copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private var explicitActions: some View {
        HStack(spacing: 12) {
            Button {
                copyExplicit()
            } label: {
                Label("Copy explicit badge", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy explicit badge"))
            .accessibilityHint(
                String(localized: "Copies the localized Explicit badge shown above to the pasteboard; display-only; does not enforce content restrictions")
            )

            ShareLink(
                item: displayExplicitShareText,
                subject: Text(resolvedTitle)
            ) {
                Label("Share explicit badge", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share explicit badge"))
            .accessibilityHint(
                String(localized: "Shares the localized Explicit badge shown above as plain text; display-only; does not enforce content restrictions")
            )
        }
    }

    private func copyExplicit() {
        UIPasteboard.general.string = displayExplicitShareText
        copiedAlertMessage = String(localized: "Explicit badge copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private var blockedActions: some View {
        HStack(spacing: 12) {
            Button {
                copyBlocked()
            } label: {
                Label("Copy blocked claim", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy blocked claim"))
            .accessibilityHint(
                String(localized: "Copies the localized Blocked capsule and its directory footnote to the pasteboard; display-only; subscribe and play still work")
            )

            ShareLink(
                item: displayBlockedShareText,
                subject: Text(resolvedTitle)
            ) {
                Label("Share blocked claim", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share blocked claim"))
            .accessibilityHint(
                String(localized: "Shares the localized Blocked capsule and its directory footnote as plain text; display-only; subscribe and play still work")
            )
        }
    }

    private func copyBlocked() {
        UIPasteboard.general.string = displayBlockedShareText
        copiedAlertMessage = String(localized: "Blocked claim copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private func mediumActions(_ medium: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyMedium(medium)
            } label: {
                Label("Copy medium", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy medium"))
            .accessibilityHint(
                String(localized: "Copies the same feed-provided medium string shown above to the pasteboard; display-only; no playback change or remapping")
            )

            ShareLink(
                item: medium,
                subject: Text(resolvedTitle)
            ) {
                Label("Share medium", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share medium"))
            .accessibilityHint(
                String(localized: "Shares the same feed-provided medium string shown above as plain text; display-only; no playback change or remapping")
            )
        }
    }

    private func copyMedium(_ medium: String) {
        UIPasteboard.general.string = medium
        copiedAlertMessage = String(localized: "Podcast medium copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private func itunesTypeActions(_ itunesType: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyItunesType(itunesType)
            } label: {
                Label("Copy podcast type", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy podcast type"))
            .accessibilityHint(
                String(localized: "Copies the same displayed Episodic, Serial, or feed-provided type string to the pasteboard; display-only; does not change sorting")
            )

            ShareLink(
                item: itunesType,
                subject: Text(resolvedTitle)
            ) {
                Label("Share podcast type", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share podcast type"))
            .accessibilityHint(
                String(localized: "Shares the same displayed Episodic, Serial, or feed-provided type string as plain text; display-only; does not change sorting")
            )
        }
    }

    private func copyItunesType(_ itunesType: String) {
        UIPasteboard.general.string = itunesType
        copiedAlertMessage = String(localized: "Podcast type copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private var categoryActions: some View {
        HStack(spacing: 12) {
            Button {
                copyCategories()
            } label: {
                Label("Copy categories", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy categories"))
            .accessibilityHint(
                String(localized: "Copies the same feed-provided category list shown above to the pasteboard; display-only; no App Store taxonomy invented")
            )

            ShareLink(
                item: displayCategoriesShareText,
                subject: Text(resolvedTitle)
            ) {
                Label("Share categories", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share categories"))
            .accessibilityHint(
                String(localized: "Shares the same feed-provided category list shown above as plain text; display-only; no App Store taxonomy invented")
            )
        }
    }

    private func copyCategories() {
        guard !displayCategories.isEmpty else { return }
        UIPasteboard.general.string = displayCategoriesShareText
        copiedAlertMessage = String(localized: "Podcast categories copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func lockedOwnerShareURL(_ owner: String) -> URL? {
        guard let url = URL(string: owner) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "mailto" || scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func copyLockedOwner(_ owner: String) {
        UIPasteboard.general.string = owner
        copiedAlertMessage = String(localized: "Locked owner copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyPodcastDescription() {
        let text = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Podcast description copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func scheduleFilter(for term: String) {
        debounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            debouncedQuery = trimmed
        }
    }
}


/// itunes:category chips for the description sheet (feed text only).
private struct FeedDescriptionCategoryChips: View {
    let categories: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(categories, id: \.self) { name in
                Text(name)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}
