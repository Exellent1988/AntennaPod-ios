import SwiftUI
import UIKit

/// Chapters list sheet mirroring Full player list UX: searchable titles, tap → seek,
/// current highlight, duration / current remaining when end known (remaining follows
/// Remaining time respects speed like mini/full −remaining), optional per-chapter
/// Open link (http(s) href), optional chapters URL.
/// Toolbar **Copy chapters** + **Copy current chapter** + **Share current chapter** +
/// **Share chapters** export a plain-text TOC / current chapter line from the **full**
/// already-known chapter array (ignores search filter) — same honesty as transcript
/// Copy/Share / Copy current cue / Share current cue.
///
/// Already-loaded chapters only — does **not** fetch remote Podcast Index JSON or
/// media-file tags (same honesty as mini Previous/Next). Full Player still lazy-loads.
struct EpisodeChaptersSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    /// Chapters already known on the episode / player (PSC / persisted remote / media).
    let chapters: [PodcastChapter]
    /// Prefer store-resolved episode for duration + chapters URL Open/Copy.
    let episode: PodcastEpisode?

    @State private var chapterSearchText = ""
    @State private var chapterDebouncedQuery = ""
    @State private var chapterDebounceTask: Task<Void, Never>?

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let chapterDebounceNs: UInt64 = 250_000_000 // 250 ms

    private var displayPosition: Double {
        playback.positionSeconds
    }

    private var currentChapterIndex: Int? {
        ChapterIndexing.currentIndex(in: chapters, at: displayPosition)
    }

    /// Visible chapter indices after light-debounced case-insensitive title filter.
    private var filteredChapterIndices: [Int] {
        let q = chapterDebouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(chapters.indices) }
        return chapters.indices.filter { chapters[$0].title.localizedCaseInsensitiveContains(q) }
    }

    private var isFilteringChapters: Bool {
        !chapterDebouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Known episode duration for last-chapter end (live player → feed → saved playback).
    /// `nil` when unknown — last chapter duration/remaining stays hidden (no invented end).
    private var chapterEpisodeDurationSeconds: Double? {
        let live = playback.durationSeconds
        if live.isFinite, live > 0 { return live }
        if let episode, episode.hasKnownDuration {
            return episode.durationSeconds
        }
        if let episode {
            let saved = store.playbackState(for: episode.id).durationSeconds
            if saved.isFinite, saved > 0 { return saved }
        }
        return nil
    }

    private var showChaptersURL: Bool {
        episode?.hasPodcastIndexChapterURL == true
    }

    /// Plain TOC from the **full** already-known chapter array — ignores search filter.
    private var chaptersTOCPlain: String {
        ChaptersTOCExport.plainText(from: chapters)
    }

    private var canExportChaptersTOC: Bool {
        !chaptersTOCPlain.isEmpty
    }

    /// Episode title + TOC body for system share sheet (same body as Copy).
    private var chaptersTOCShareText: String {
        ChaptersTOCExport.shareText(from: chapters, episodeTitle: episode?.title)
    }

    /// One-line pasteboard text for the chapter active at playback position (full loaded array).
    /// Same TOC line format as Copy chapters; uses `ChapterIndexing.currentIndex`.
    private var currentChapterPlainForCopy: String? {
        ChaptersTOCExport.currentChapterPlainText(from: chapters, at: displayPosition)
    }

    /// Enabled when `ChapterIndexing` reports a current chapter (nil when empty / before first).
    private var canCopyCurrentChapter: Bool {
        currentChapterPlainForCopy != nil
    }

    /// Same gate as Copy current chapter — Share only when a current chapter exists.
    private var canShareCurrentChapter: Bool { canCopyCurrentChapter }

    /// Episode title + one-line current chapter for system share sheet (same body as Copy).
    private var currentChapterShareText: String {
        ChaptersTOCExport.currentChapterShareText(
            from: chapters,
            at: displayPosition,
            episodeTitle: episode?.title
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "No chapters available",
                        systemImage: "list.bullet",
                        description: Text(String(localized: "No chapters known for this episode yet."))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No chapters available"))
                    .accessibilityValue(String(localized: "No chapters are known for this episode yet."))
                } else if isFilteringChapters && filteredChapterIndices.isEmpty {
                    ContentUnavailableView(
                        "No matching chapters",
                        systemImage: "magnifyingglass",
                        description: Text("No chapters match your search.")
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No matching chapters"))
                    .accessibilityValue(String(localized: "No chapters match your search."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredChapterIndices, id: \.self) { index in
                                chapterRow(index: index)
                            }
                            if let ep = episode, showChaptersURL {
                                PodcastChaptersURLView(episode: ep, showsSectionTitle: true)
                                    .padding(.top, 12)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(String(localized: "Chapters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyChaptersTOC()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!canExportChaptersTOC)
                    .accessibilityLabel(String(localized: "Copy chapters"))
                    .accessibilityHint(String(localized: "Copies the chapter table of contents to the pasteboard"))

                    Button {
                        copyCurrentChapter()
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .disabled(!canCopyCurrentChapter)
                    .accessibilityLabel(String(localized: "Copy current chapter"))
                    .accessibilityHint(
                        String(localized: "Copies the current chapter to the pasteboard")
                    )

                    ShareLink(
                        item: currentChapterShareText,
                        subject: Text(episode?.title ?? String(localized: "Chapters"))
                    ) {
                        Image(systemName: "quote.bubble")
                    }
                    .disabled(!canShareCurrentChapter)
                    .accessibilityLabel(String(localized: "Share current chapter"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and current chapter")
                    )

                    ShareLink(
                        item: chaptersTOCShareText,
                        subject: Text(episode?.title ?? String(localized: "Chapters"))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!canExportChaptersTOC)
                    .accessibilityLabel(String(localized: "Share chapters"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and chapter table of contents")
                    )
                }
            }
            .searchable(text: $chapterSearchText, prompt: "Search chapters")
            .onChange(of: chapterSearchText) { _, newValue in
                scheduleChapterFilter(for: newValue)
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
        .presentationDetents([.medium, .large])
        .onDisappear {
            chapterDebounceTask?.cancel()
        }
    }

    @ViewBuilder
    private func chapterRow(index: Int) -> some View {
        let chapter = chapters[index]
        ChapterListRow(
            startTimeText: format(chapter.startTimeSeconds),
            title: chapter.title,
            imageURL: chapter.displayImageURL,
            linkURL: chapter.displayLinkURL,
            trailingTimeLabel: chapterTrailingTimeLabel(index: index),
            isCurrent: index == currentChapterIndex,
            accessibilityBaseLabel: chapterAccessibilityLabel(index: index, chapter: chapter),
            onSeek: {
                playback.seek(toSeconds: chapter.startTimeSeconds)
            }
        )
    }

    /// Trailing time for a chapter row: current → live remaining (−m:ss) when end known;
    /// otherwise chapter duration when known. Hidden when times cannot be derived honestly.
    /// Current remaining follows Settings → Remaining time respects speed (same as mini/full
    /// −remaining); chapter **duration** stays wall-clock.
    private func chapterTrailingTimeLabel(index: Int) -> String? {
        let episodeDuration = chapterEpisodeDurationSeconds
        if index == currentChapterIndex,
           let wall = ChapterIndexing.remainingSeconds(
               in: chapters,
               atIndex: index,
               positionSeconds: displayPosition,
               episodeDurationSeconds: episodeDuration
           ) {
            return formatRemaining(displayChapterRemainingSeconds(wall))
        }
        if let duration = ChapterIndexing.durationSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: episodeDuration
        ) {
            return format(duration)
        }
        return nil
    }

    private func chapterAccessibilityLabel(index: Int, chapter: PodcastChapter) -> String {
        var parts = [String(localized: "Chapter \(chapter.title), \(format(chapter.startTimeSeconds))")]
        let episodeDuration = chapterEpisodeDurationSeconds
        if index == currentChapterIndex,
           let wall = ChapterIndexing.remainingSeconds(
               in: chapters,
               atIndex: index,
               positionSeconds: displayPosition,
               episodeDurationSeconds: episodeDuration
           ) {
            let display = displayChapterRemainingSeconds(wall)
            parts.append(String(localized: "\(format(display)) remaining"))
        } else if let duration = ChapterIndexing.durationSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: episodeDuration
        ) {
            parts.append(String(localized: "Duration \(format(duration))"))
        }
        return parts.joined(separator: ", ")
    }

    /// Current-chapter remaining for list chrome. Wall-clock unless Remaining time respects
    /// speed — then ÷ live session rate when this episode is current (else feed/default),
    /// clamped 0.5…3.0. Same helper as mini/full −remaining. Not Lock Screen / Widget / Watch.
    private func displayChapterRemainingSeconds(_ wallClockSeconds: Double) -> Double {
        let episodeForSpeed = episode ?? playback.currentEpisode
        let fallback: Float
        if let episodeForSpeed {
            fallback = store.resolvedPlaybackSpeedForRemaining(for: episodeForSpeed)
        } else {
            fallback = max(
                EpisodeRemainingTime.minimumPlaybackSpeedDivisor,
                settings.defaultPlaybackSpeed
            )
        }
        // Prefer live session rate only while this sheet’s episode is the current player item.
        let sessionRate: Float
        if let episodeForSpeed, playback.currentEpisode?.id == episodeForSpeed.id {
            sessionRate = playback.rate
        } else {
            sessionRate = 0 // force fallback via playerChromeSpeedDivisor
        }
        return EpisodeRemainingTime.playerChromeRemainingSeconds(
            wallClockSeconds: wallClockSeconds,
            respectsSpeed: settings.remainingTimeRespectsSpeed,
            sessionRate: sessionRate,
            fallbackSpeed: fallback
        )
    }

    private func scheduleChapterFilter(for term: String) {
        chapterDebounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            chapterDebouncedQuery = ""
            return
        }
        chapterDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: chapterDebounceNs)
            guard !Task.isCancelled else { return }
            chapterDebouncedQuery = trimmed
        }
    }

    private func copyChaptersTOC() {
        let text = chaptersTOCPlain
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Chapters copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyCurrentChapter() {
        guard let text = currentChapterPlainForCopy, !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Current chapter copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Remaining time with a leading minus (−m:ss or −h:mm:ss).
    private func formatRemaining(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "-%d:%02d:%02d", h, m, s)
        }
        return String(format: "-%d:%02d", m, s)
    }
}
