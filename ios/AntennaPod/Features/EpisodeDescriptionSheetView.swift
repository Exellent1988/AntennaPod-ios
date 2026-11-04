import SwiftUI
import UIKit

/// Scrollable episode shownotes / description sheet (plain text; HTML stripped for beta).
/// Supports `.searchable` filter over already-loaded plain paragraphs/lines (case-insensitive,
/// ~250 ms debounce). Does not fetch remote HTML beyond the episode's feed description —
/// no WebView / rich HTML renderer.
struct EpisodeDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService

    let episode: PodcastEpisode
    /// Optional podcast name for share message (`Title — Podcast`). When empty, looked up from the store.
    var feedTitle: String? = nil

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var plainDescription: String {
        guard let raw = episode.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var hasPlainShownotes: Bool {
        !plainDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Full plain shownotes body with an episode-title header for system sharing.
    /// This intentionally ignores the searchable, visible subset.
    private var shownotesShareText: String {
        let body = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = title.isEmpty ? String(localized: "Shownotes") : title
        return "\(header)\n\n\(body)"
    }

    private var shownotesShareSubject: String {
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Shownotes") : title
    }

    /// Item podcast:person when the feed provided them — empty → hide (never invent).
    private var displayPeople: [PodcastPerson] {
        episode.displayPeople
    }

    private var hasPeople: Bool {
        !displayPeople.isEmpty
    }

    /// Item podcast:location when the feed provided them — empty → hide (never invent / never geocode).
    private var displayLocations: [PodcastLocation] {
        episode.displayLocations
    }

    private var hasLocations: Bool {
        !displayLocations.isEmpty
    }

    /// Item podcast:socialInteract when the feed provided openable http(s) — empty → hide (never invent).
    private var displaySocialInteracts: [PodcastSocialInteract] {
        episode.displaySocialInteracts
    }

    private var hasSocialInteracts: Bool {
        !displaySocialInteracts.isEmpty
    }

    /// Item podcast:value when the feed provided recipients — empty → hide (display-only; no payments).
    private var displayValues: [PodcastValue] {
        episode.values
    }

    private var hasValues: Bool {
        !episode.displayValueRecipients.isEmpty
    }

    /// Item podcast:alternateEnclosure when the feed provided options — empty → hide (http(s) Play + Open; else Copy).
    private var displayAlternateEnclosures: [PodcastAlternateEnclosure] {
        episode.alternateEnclosures
    }

    private var hasAlternateEnclosures: Bool {
        !episode.displayAlternateEnclosures.isEmpty
    }

    /// Item podcast:soundbite when the feed provided clips — empty → hide (Play soundbite / Copy; no separate clip player).
    private var displaySoundbites: [PodcastSoundbite] {
        episode.soundbites
    }

    private var hasSoundbites: Bool {
        !episode.displaySoundbites.isEmpty
    }

    /// Item podcast:txt when the feed provided entries — empty → hide (display-only Copy / Share / Open).
    private var displayTexts: [PodcastTxt] {
        episode.texts
    }

    private var hasTexts: Bool {
        !episode.displayTexts.isEmpty
    }

    /// Item podcast:license when the feed provided entries — empty → hide (display-only; no DRM).
    private var displayLicenses: [PodcastLicense] {
        episode.licenses
    }

    private var hasLicenses: Bool {
        !episode.displayLicenses.isEmpty
    }

    /// Item podcast:images / podcast:image when the feed provided variants — empty → hide.
    private var displayImages: [PodcastImageVariant] {
        episode.images
    }

    private var hasImages: Bool {
        !episode.displayImages.isEmpty
    }

    /// Item podcast:chapters remote URL when set — Open / Copy; hide when missing (never invent).
    private var hasChaptersURL: Bool {
        episode.hasPodcastIndexChapterURL
    }

    /// Item itunes:episodeType when set — Full/Trailer/Bonus or raw; hide when missing (never invent).
    private var displayEpisodeType: String? {
        episode.displayEpisodeType
    }

    private var hasEpisodeType: Bool {
        displayEpisodeType != nil
    }

    /// Compact S2 E5 when itunes:season / itunes:episode present.
    private var seasonEpisodeCaption: String? {
        episode.seasonEpisodeCaption
    }

    private var formattedKnownDuration: String? {
        EpisodeCopyLinks.formattedDuration(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    private var formattedKnownByteSize: String? {
        EpisodeCopyLinks.formattedByteSize(for: episode, downloads: downloads)
    }

    /// Same publish-date caption shown in EpisodeRow; hidden when feed metadata is missing.
    private var formattedPublishDate: String? {
        EpisodeCopyLinks.formattedPublishDate(for: episode)
    }

    private var hasEpisodeMeta: Bool {
        hasEpisodeType
            || seasonEpisodeCaption != nil
            || episode.isExplicit
            || episode.displayMedium != nil
            || formattedPublishDate != nil
            || formattedKnownDuration != nil
            || formattedKnownByteSize != nil
            || EpisodeCopyLinks.trimmedTitle(for: episode) != nil
            || EpisodeCopyLinks.trimmedFeedTitle(resolvedFeedTitle) != nil
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

    private var resolvedFeed: PodcastFeed? {
        store.feed(containingEpisodeId: episode.id)
    }

    private var resolvedFeedTitle: String {
        if let feedTitle, !feedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return feedTitle
        }
        guard let resolvedFeed else { return "" }
        return store.displayTitle(for: resolvedFeed)
    }

    private var shareURL: URL? {
        episode.shareURL(feed: resolvedFeed)
    }

    private var shareMessage: String {
        episode.shareMessage(feedTitle: resolvedFeedTitle)
    }

    /// Only when this shownotes episode is the current playback item and position is known.
    private var canShareWithPosition: Bool {
        playback.currentEpisode?.id == episode.id
            && PodcastEpisode.canShareWithPosition(playback.positionSeconds)
    }

    private var shareMessageWithPosition: String {
        episode.shareMessage(
            feedTitle: resolvedFeedTitle,
            positionSeconds: playback.positionSeconds
        )
    }

    private var websiteURL: URL? {
        episode.websiteURL
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty && !hasPeople && !hasLocations && !hasSocialInteracts && !hasValues && !hasAlternateEnclosures && !hasSoundbites && !hasTexts && !hasLicenses && !hasChaptersURL && !hasEpisodeMeta {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "doc.text",
                        description: Text("This episode has no shownotes in the feed.")
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "No description"))
                    .accessibilityValue(String(localized: "This episode has no shownotes in the feed."))
                    .accessibilityHint(String(localized: "There is no episode description to read."))
                } else if plainDescription.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            episodeMetaCapsules
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
                            if hasAlternateEnclosures {
                                PodcastAlternateEnclosuresListView(alternateEnclosures: displayAlternateEnclosures, episode: episode)
                            }
                            if hasSoundbites {
                                PodcastSoundbitesListView(soundbites: displaySoundbites, episode: episode)
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
                            if hasChaptersURL {
                                PodcastChaptersURLView(episode: episode)
                            }
                        }
                        .padding()
                    }
                } else {
                    shownotesContent
                        .searchable(text: $searchText, prompt: "Search shownotes")
                        .onChange(of: searchText) { _, newValue in
                            scheduleFilter(for: newValue)
                        }
                }
            }
            .navigationTitle("Shownotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyShownotes()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!hasPlainShownotes)
                    .accessibilityLabel(String(localized: "Copy shownotes"))
                    .accessibilityHint(String(localized: "Copies the full episode shownotes as plain text with HTML stripped to the pasteboard. Ignores the shownotes search filter. No confirmation. Distinct from Share shownotes. Does not open a browser, download, play, mark played, or change the queue."))

                    ShareLink(
                        item: shownotesShareText,
                        subject: Text(shownotesShareSubject)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!hasPlainShownotes)
                    .accessibilityLabel(String(localized: "Share shownotes"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the full shownotes as plain text, with HTML stripped; ignores search filters")
                    )

                    if let url = websiteURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(String(localized: "Open episode website"))
                        .accessibilityHint(String(localized: "Opens the feed-provided episode webpage http(s) link in the system browser — not an in-app WebView. No confirmation. Never uses the enclosure or podcast website URL. Distinct from Copy episode link, Copy media URL, and Share episode. Does not download, play, mark played, or change the queue."))

                        Button {
                            copyEpisodeLink(url)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(String(localized: "Copy episode link"))
                        .accessibilityHint(String(localized: "Copies the feed-provided episode webpage http(s) link to the pasteboard. No confirmation. Never silently copies the enclosure as the episode link. Distinct from Copy media URL and Share episode. Does not open the browser, download, play, mark played, or change the queue."))

                        EpisodeShareLinks.episodeLinkLabelStyle(episode: episode)
                    }
                    if let rawMediaURL = episode.mediaURLString {
                        Button {
                            copyMediaURL(rawMediaURL)
                        } label: {
                            Image(systemName: "link")
                        }
                        .accessibilityLabel(String(localized: "Copy media URL"))
                        .accessibilityHint(String(localized: "Copies the feed-provided episode media / enclosure http(s) URL to the pasteboard. No confirmation. Hidden for local file or local-folder URLs. Distinct from Copy episode link and Share episode. Does not download, play, mark played, or change the queue."))

                        EpisodeShareLinks.mediaURLLabelStyle(episode: episode)
                    }
                    if let url = shareURL {
                        ShareLink(
                            item: url,
                            subject: Text(episode.title),
                            message: Text(shareMessage)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share episode"))
                        .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and best network link (episode page, enclosure, feed homepage, or feed URL). Local file URLs are not shared. Does not include a playback position — use Share with position for that."))

                        if canShareWithPosition {
                            ShareLink(
                                item: url,
                                subject: Text(episode.title),
                                message: Text(shareMessageWithPosition)
                            ) {
                                Image(systemName: "square.and.arrow.up.on.square")
                            }
                            .accessibilityLabel(String(localized: "Share with position"))
                            .accessibilityHint(
                                String(localized: "Opens the system share sheet with the episode title, best network link (episode page, enclosure, feed homepage, or feed URL), and a readable position timestamp in the message. Local file URLs are not shared. The shared link is unchanged — no #t= seek fragment.")
                            )
                        }
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
            .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    @ViewBuilder
    private var shownotesContent: some View {
        if isFiltering && filteredParagraphs.isEmpty {
            ContentUnavailableView(
                "No matching text",
                systemImage: "magnifyingglass",
                description: Text("No shownotes text matches your search.")
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "No matching text"))
            .accessibilityValue(String(localized: "No shownotes text matches your search."))
            .accessibilityHint(String(localized: "Change or clear the shownotes search to see other text."))
        } else if isFiltering {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    episodeMetaCapsules
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
                    if hasAlternateEnclosures {
                        PodcastAlternateEnclosuresListView(alternateEnclosures: displayAlternateEnclosures, episode: episode)
                    }
                    if hasSoundbites {
                        PodcastSoundbitesListView(soundbites: displaySoundbites, episode: episode)
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
                    if hasChaptersURL {
                        PodcastChaptersURLView(episode: episode)
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
                VStack(alignment: .leading, spacing: 16) {
                    episodeMetaCapsules
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
                    if hasAlternateEnclosures {
                        PodcastAlternateEnclosuresListView(alternateEnclosures: displayAlternateEnclosures, episode: episode)
                    }
                    if hasSoundbites {
                        PodcastSoundbitesListView(soundbites: displaySoundbites, episode: episode)
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
                    if hasChaptersURL {
                        PodcastChaptersURLView(episode: episode)
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
    private var episodeMetaCapsules: some View {
        if hasEpisodeMeta {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let seasonEpisodeCaption {
                        Text(seasonEpisodeCaption)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(episode.seasonEpisodeAccessibilityLabel ?? seasonEpisodeCaption)
                    }
                    if episode.isExplicit {
                        Text(String(localized: "Explicit"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(String(localized: "Explicit"))
                    }
                    if let medium = episode.displayMedium {
                        Text(medium)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(String(localized: "Medium \(medium)"))
                    }
                    if let formattedPublishDate {
                        Text(formattedPublishDate)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(String(localized: "Publish date \(formattedPublishDate)"))
                    }
                    if let episodeType = displayEpisodeType {
                        Text(episodeType)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(episode.episodeTypeAccessibilityLabel ?? episodeType)
                    }
                    if let formattedKnownDuration {
                        Text(formattedKnownDuration)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(String(localized: "Duration \(formattedKnownDuration)"))
                    }
                    if let formattedKnownByteSize {
                        Text(formattedKnownByteSize)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .accessibilityLabel(String(localized: "Size \(formattedKnownByteSize)"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let seasonEpisodeCaption {
                    episodeMetadataActions(
                        text: seasonEpisodeCaption,
                        copyLabel: String(localized: "Copy season and episode"),
                        shareLabel: String(localized: "Share season and episode"),
                        copyHint: String(localized: "Copies the same season and episode caption shown above to the pasteboard; item metadata only; no numbers invented"),
                        shareHint: String(localized: "Shares the same season and episode caption shown above as plain text; item metadata only; no numbers invented"),
                        copiedMessage: String(localized: "Season and episode copied to the pasteboard.")
                    )
                }
                if episode.isExplicit {
                    episodeMetadataActions(
                        text: String(localized: "Explicit"),
                        copyLabel: String(localized: "Copy episode explicit badge"),
                        shareLabel: String(localized: "Share episode explicit badge"),
                        copyHint: String(localized: "Copies the localized Explicit badge shown above for this episode to the pasteboard; display-only; does not enforce content restrictions"),
                        shareHint: String(localized: "Shares the localized Explicit badge shown above for this episode as plain text; display-only; does not enforce content restrictions"),
                        copiedMessage: String(localized: "Episode explicit badge copied to the pasteboard.")
                    )
                }
                if let medium = episode.displayMedium {
                    episodeMetadataActions(
                        text: medium,
                        copyLabel: String(localized: "Copy episode medium"),
                        shareLabel: String(localized: "Share episode medium"),
                        copyHint: String(localized: "Copies the same item-provided medium string shown above to the pasteboard; display-only; no playback change or remapping"),
                        shareHint: String(localized: "Shares the same item-provided medium string shown above as plain text; display-only; no playback change or remapping"),
                        copiedMessage: String(localized: "Episode medium copied to the pasteboard.")
                    )
                }
                if let episodeType = displayEpisodeType {
                    episodeMetadataActions(
                        text: episodeType,
                        copyLabel: String(localized: "Copy episode type"),
                        shareLabel: String(localized: "Share episode type"),
                        copyHint: String(localized: "Copies the same item itunes:episodeType label shown above to the pasteboard; distinct from channel podcast:trailer"),
                        shareHint: String(localized: "Shares the same item itunes:episodeType label shown above as plain text; distinct from channel podcast:trailer"),
                        copiedMessage: String(localized: "Episode type copied to the pasteboard.")
                    )
                }
                if let formattedPublishDate {
                    episodeMetadataActions(
                        text: formattedPublishDate,
                        copyLabel: String(localized: "Copy episode publish date"),
                        shareLabel: String(localized: "Share episode publish date"),
                        copyHint: String(localized: "Copies the same publish-date caption shown above to the pasteboard; known feed metadata only; no date invented"),
                        shareHint: String(localized: "Shares the same publish-date caption shown above as plain text; known feed metadata only; no date invented"),
                        copiedMessage: String(localized: "Episode publish date copied to the pasteboard.")
                    )
                }
                if let formattedKnownDuration {
                    episodeMetadataActions(
                        text: formattedKnownDuration,
                        copyLabel: String(localized: "Copy episode duration"),
                        shareLabel: String(localized: "Share episode duration"),
                        copyHint: String(localized: "Copies the same duration caption shown above to the pasteboard; feed or known playback metadata only; no length invented"),
                        shareHint: String(localized: "Shares the same duration caption shown above as plain text; feed or known playback metadata only; no length invented"),
                        copiedMessage: String(localized: "Episode duration copied to the pasteboard.")
                    )
                }
                if let formattedKnownByteSize {
                    episodeMetadataActions(
                        text: formattedKnownByteSize,
                        copyLabel: String(localized: "Copy episode file size"),
                        shareLabel: String(localized: "Share episode file size"),
                        copyHint: String(localized: "Copies the same file-size caption shown above to the pasteboard; on-disk or feed enclosure metadata only; no size invented"),
                        shareHint: String(localized: "Shares the same file-size caption shown above as plain text; on-disk or feed enclosure metadata only; no size invented"),
                        copiedMessage: String(localized: "Episode file size copied to the pasteboard.")
                    )
                }
                if let podcastTitle = EpisodeCopyLinks.trimmedFeedTitle(resolvedFeedTitle) {
                    Text(podcastTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Podcast title"))
                        .accessibilityValue(podcastTitle)
                    episodeMetadataActions(
                        text: podcastTitle,
                        copyLabel: String(localized: "Copy podcast title"),
                        shareLabel: String(localized: "Share podcast title"),
                        copyHint: String(localized: "Copies the trimmed podcast display title to the pasteboard; hidden when the title is empty; no title invented"),
                        shareHint: String(localized: "Shares the trimmed podcast display title as plain text; hidden when the title is empty; no title invented"),
                        copiedMessage: String(localized: "Podcast title copied to the pasteboard.")
                    )
                }
                if let title = EpisodeCopyLinks.trimmedTitle(for: episode) {
                    episodeMetadataActions(
                        text: title,
                        copyLabel: String(localized: "Copy episode title"),
                        shareLabel: String(localized: "Share episode title"),
                        copyHint: String(localized: "Copies the trimmed episode title to the pasteboard; hidden when the title is empty; no title invented"),
                        shareHint: String(localized: "Shares the trimmed episode title as plain text; hidden when the title is empty; no title invented"),
                        copiedMessage: String(localized: "Episode title copied to the pasteboard.")
                    )
                }
                if let titleAndPodcast = EpisodeCopyLinks.trimmedTitleAndPodcast(
                    episode: episode,
                    feedTitle: resolvedFeedTitle
                ) {
                    episodeMetadataActions(
                        text: titleAndPodcast,
                        copyLabel: String(localized: "Copy title and podcast"),
                        shareLabel: String(localized: "Share title and podcast"),
                        copyHint: String(localized: "Copies the trimmed episode title and podcast display title as `title — podcast`; hidden unless both are present; no title invented"),
                        shareHint: String(localized: "Shares the trimmed episode title and podcast display title as `title — podcast` plain text; hidden unless both are present; no title invented"),
                        copiedMessage: String(localized: "Title and podcast copied to the pasteboard.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func episodeMetadataActions(
        text: String,
        copyLabel: String,
        shareLabel: String,
        copyHint: String,
        shareHint: String,
        copiedMessage: String
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                copyEpisodeMetadata(text, message: copiedMessage)
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(copyLabel)
            .accessibilityHint(copyHint)

            ShareLink(
                item: text,
                subject: Text(episode.title)
            ) {
                Label(shareLabel, systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(shareLabel)
            .accessibilityHint(shareHint)
        }
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

    private func copyShownotes() {
        let text = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Shownotes copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyEpisodeLink(_ url: URL) {
        copiedAlertMessage = EpisodeCopyLinks.copyEpisodeLink(url)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ rawURL: String) {
        copiedAlertMessage = EpisodeCopyLinks.copyMediaURL(rawURL)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyEpisodeMetadata(_ text: String, message: String) {
        UIPasteboard.general.string = text
        copiedAlertMessage = message
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }
}
