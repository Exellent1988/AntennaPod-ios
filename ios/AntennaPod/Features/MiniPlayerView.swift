import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @Environment(\.openURL) private var openURL
    @State private var showFullPlayer = false
    /// Incoming subscribe link closes the Full Player first (`SubscribeLinkRouter`).
    @ObservedObject private var subscribeLink = SubscribeLinkRouter.shared
    @State private var showFeedUnavailable = false
    @State private var showCustomSleepTimer = false
    @State private var showCustomPlaybackSpeed = false
    @State private var showBookmarks = false
    @State private var showEpisodePrivateNote = false
    @State private var showChapters = false
    @State private var showAtCapAlert = false
    @State private var bookmarkAddedTick = 0
    @State private var showJumpToPosition = false
    @State private var showDescription = false
    @State private var showTranscript = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0
    /// Single episode pending mini ⋯ Remove-from-queue confirmation (nil = dialog dismissed).
    @State private var episodePendingRemoveFromQueue: PodcastEpisode?
    /// Single episode pending mini ⋯ Delete-download confirmation (nil = dialog dismissed).
    @State private var episodePendingDeleteDownload: PodcastEpisode?

    var body: some View {
        if let episode = playback.currentEpisode {
            VStack(spacing: 8) {
                Button {
                    showFullPlayer = true
                } label: {
                    ProgressView(value: playback.durationSeconds > 0 ? playback.positionSeconds / playback.durationSeconds : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Open full player"))
                .accessibilityHint(String(localized: "Shows the full player with scrubber and more controls"))
                .accessibilityValue(timeLabel)

                HStack {
                    Button {
                        showFullPlayer = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            if let chapterTitle = currentChapterTitle {
                                Text(chapterTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                Text(timeLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                sourceIndicator
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openFullPlayerAccessibilityLabel(for: episode))

                    Button {
                        playback.seek(bySeconds: -playback.rewindSeconds)
                    } label: {
                        Image(systemName: AppSettings.skipSystemImage(forward: false, seconds: settings.rewindSeconds))
                    }
                    .accessibilityLabel(String(localized: "Rewind \(settings.rewindSeconds) seconds"))
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(playback.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                    Button {
                        playback.seek(bySeconds: playback.fastForwardSeconds)
                    } label: {
                        Image(systemName: AppSettings.skipSystemImage(forward: true, seconds: settings.fastForwardSeconds))
                    }
                    .accessibilityLabel(String(localized: "Forward \(settings.fastForwardSeconds) seconds"))
                    sleepTimerMenu
                    Menu {
                        ForEach(AppSettings.speedPresets, id: \.self) { speed in
                            Button {
                                playback.setRate(speed)
                            } label: {
                                HStack {
                                    Text(PlaybackService.formatPlaybackSpeed(speed))
                                    if speed == settings.defaultPlaybackSpeed {
                                        Text("Default")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button(String(localized: "Custom…")) {
                            showCustomPlaybackSpeed = true
                        }
                    } primaryAction: {
                        playback.cycleToNextSpeedPreset()
                    } label: {
                        Text(PlaybackService.formatPlaybackSpeed(playback.rate))
                            .font(.caption.monospacedDigit())
                    }
                    .accessibilityLabel("\(String(localized: "Playback speed")) \(PlaybackService.formatPlaybackSpeed(playback.rate))")
                    .accessibilityHint(String(localized: "Cycles the session playback speed through presets. Does not change Default speed or this podcast’s speed override. Long-press for the full list and Custom…. Not Volume boost or Preserve pitch."))

                    Menu {
                        Button {
                            openPodcastFromMiniPlayer()
                        } label: {
                            Label("Open podcast", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(feedForCurrentEpisode == nil)
                        Button {
                            showDescription = true
                        } label: {
                            Label("Shownotes", systemImage: "doc.text")
                        }
                        .accessibilityLabel(String(localized: "Show shownotes"))
                        .accessibilityHint(
                            episode.hasDescriptionText
                                ? String(localized: "Opens the episode description from the feed")
                                : String(localized: "No description available for this episode")
                        )
                        // Transcript — same hasTranscriptURL gate as Full; prefer store episode.
                        // Hidden when feed provides no podcast:transcript URL (no Whisper/STT).
                        if (store.episode(id: episode.id) ?? episode).hasTranscriptURL {
                            Button {
                                showTranscript = true
                            } label: {
                                Label("Transcript", systemImage: "text.bubble")
                            }
                            .accessibilityLabel(String(localized: "Show transcript"))
                            .accessibilityHint(String(localized: "Opens the feed-provided transcript"))
                        }
                        Button {
                            playback.playFromBeginning()
                        } label: {
                            Label("Play from beginning", systemImage: "backward.end.fill")
                        }
                        .accessibilityLabel(String(localized: "Play from beginning"))
                        .accessibilityHint(String(localized: "Seeks to the start of this episode and plays"))
                        // Previous / Next chapter — same ChapterIndexing + seek as Full transport.
                        // Only when chapters already on store/player episode (no mini lazy fetch).
                        if canSkipChapters {
                            Button {
                                if let target = previousChapterTarget {
                                    playback.jumpToPosition(seconds: target)
                                }
                            } label: {
                                Label("Previous chapter", systemImage: "backward.end.fill")
                            }
                            .disabled(previousChapterTarget == nil)
                            .accessibilityLabel(String(localized: "Previous chapter"))
                            .accessibilityHint(String(localized: "Seeks to the previous chapter, or restarts the current chapter if more than 2 seconds in"))
                            Button {
                                if let target = nextChapterTarget {
                                    playback.jumpToPosition(seconds: target)
                                }
                            } label: {
                                Label("Next chapter", systemImage: "forward.end.fill")
                            }
                            .disabled(nextChapterTarget == nil)
                            .accessibilityLabel(String(localized: "Next chapter"))
                            .accessibilityHint(nextChapterAccessibilityHint)
                            // Chapters list — same searchable list + seek as Full (EpisodeChaptersSheet).
                            // Only when chapters already on store/player episode (no mini lazy fetch).
                            Button {
                                showChapters = true
                            } label: {
                                Label("Chapters", systemImage: "list.bullet")
                            }
                            .accessibilityLabel(String(localized: "Chapters"))
                            .accessibilityHint(String(localized: "Lists chapters for this episode; tap a chapter to seek. A chapter start at or past a known duration finishes the episode the same way as a forward skip."))
                        }
                        // Add bookmark — one-tap at current wall-clock position (empty note).
                        // Same 50/episode cap as Full sheet: disabled at cap + honesty alert.
                        Button {
                            addBookmarkFromMini()
                        } label: {
                            Label(
                                String(localized: "Add bookmark"),
                                systemImage: "bookmark.fill"
                            )
                        }
                        .disabled(!canAddBookmark)
                        .accessibilityLabel(String(localized: "Add bookmark"))
                        .accessibilityHint(addBookmarkAccessibilityHint)
                        .accessibilityValue(format(playback.positionSeconds))
                        Button {
                            showBookmarks = true
                        } label: {
                            Label("Bookmarks", systemImage: "bookmark")
                        }
                        .accessibilityLabel(String(localized: "Bookmarks"))
                        .accessibilityHint(String(localized: "Lists bookmarks for this episode and saves the current position"))
                        .accessibilityValue(bookmarksAccessibilityValue(for: episode.id))
                        Button {
                            showEpisodePrivateNote = true
                        } label: {
                            Label(
                                String(localized: "Private note…"),
                                systemImage: store.hasEpisodePrivateNote(for: episode.id) ? "note.text" : "square.and.pencil"
                            )
                        }
                        .accessibilityLabel(String(localized: "Private note"))
                        .accessibilityHint(String(localized: "Opens the private note editor for this episode"))
                        .accessibilityValue(
                            store.hasEpisodePrivateNote(for: episode.id)
                                ? String(localized: "Has private note")
                                : String(localized: "Empty")
                        )
                        Button {
                            showJumpToPosition = true
                        } label: {
                            Label("Jump to position", systemImage: "arrow.right.to.line")
                        }
                        .disabled(!canJumpToPosition)
                        .accessibilityHint(
                            canJumpToPosition
                                ? String(localized: "Enter a time to seek")
                                : String(localized: "Duration unknown — jump unavailable.")
                        )
                        // Library actions — same PodcastStore toggles / labels / symbols as Full secondary.
                        // State from store side maps (isPlayed / isFavorite / isArchived); id from current episode.
                        Button {
                            store.togglePlayed(episode.id)
                        } label: {
                            Label(
                                store.isPlayed(episode.id) ? String(localized: "Mark unplayed") : String(localized: "Mark played"),
                                systemImage: store.isPlayed(episode.id) ? "circle" : "checkmark.circle"
                            )
                        }
                        .accessibilityLabel(
                            store.isPlayed(episode.id)
                                ? String(localized: "Mark unplayed")
                                : String(localized: "Mark played")
                        )
                        .accessibilityHint(
                            store.isPlayed(episode.id)
                                ? String(localized: "Marks this episode as unplayed")
                                : String(localized: "Marks this episode as played")
                        )
                        Button {
                            store.toggleFavorite(episode.id)
                        } label: {
                            Label(
                                store.isFavorite(episode.id) ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                                systemImage: store.isFavorite(episode.id) ? "star.fill" : "star"
                            )
                        }
                        .accessibilityLabel(
                            store.isFavorite(episode.id)
                                ? String(localized: "Remove from favorites")
                                : String(localized: "Add to favorites")
                        )
                        .accessibilityHint(
                            store.isFavorite(episode.id)
                                ? String(localized: "Removes this episode from Favorites. No confirmation. Does not delete downloads, archive, mark played, or clear the queue.")
                                : String(localized: "Adds this episode to Favorites. No confirmation. Does not download, archive, mark played, or change the queue.")
                        )
                        Button {
                            store.toggleArchived(episode.id)
                        } label: {
                            Label(
                                store.isArchived(episode.id) ? String(localized: "Restore") : String(localized: "Archive"),
                                systemImage: store.isArchived(episode.id) ? "archivebox.fill" : "archivebox"
                            )
                        }
                        .accessibilityLabel(
                            store.isArchived(episode.id)
                                ? String(localized: "Restore")
                                : String(localized: "Archive")
                        )
                        .accessibilityHint(
                            store.isArchived(episode.id)
                                ? String(localized: "Restores this episode from the archive")
                                : String(localized: "Hides this episode from Inbox without marking it played")
                        )
                        // Queue submenu — same EpisodeQueueActions as Full secondary (nested to avoid overcrowding).
                        EpisodeQueueActions.menu(
                            episode: store.episode(id: episode.id) ?? episode,
                            store: store,
                            currentlyPlayingId: playback.currentEpisode?.id,
                            queueLocked: settings.queueLocked,
                            onRequestRemoveFromQueue: { episodePendingRemoveFromQueue = $0 }
                        )
                        // Download / Cancel / Delete — same DownloadService APIs as Full secondary.
                        // Prefer store episode (post-refresh) over a possibly stale player copy.
                        // Hidden for local-folder / file:// via EpisodeDownloadActions.canManageDownload.
                        EpisodeDownloadActions.button(
                            episode: store.episode(id: episode.id) ?? episode,
                            downloads: downloads,
                            onRequestDeleteDownload: { episodePendingDeleteDownload = $0 }
                        )
                        // Open episode website — same websiteURL gate as Full (http(s) link only).
                        // Prefer store episode (post-refresh) over a possibly stale player copy.
                        EpisodeOpenWebsite.button(
                            episode: store.episode(id: episode.id) ?? episode,
                            openURL: openURL
                        )
                        // Copy episode link / Copy media URL — same websiteURL / mediaURL gates as Full.
                        // Prefer store episode (post-refresh) over a possibly stale player copy.
                        EpisodeCopyLinks.labelStyle(
                            episode: store.episode(id: episode.id) ?? episode,
                            onCopied: { message in
                                copiedAlertMessage = message
                                copyURLFeedbackTick += 1
                                showCopiedAlert = true
                            }
                        )
                        // Current episode only (mini always shows current). Hidden when nothing shareable.
                        EpisodeShareLinks.labelStyle(
                            episode: episode,
                            feed: feedForCurrentEpisode,
                            positionSeconds: playback.positionSeconds,
                            feedDisplayTitle: feedForCurrentEpisode.map { store.displayTitle(for: $0) }
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "Player options"))
                }
            }
            .padding()
            .background(.bar)
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
            .onChange(of: subscribeLink.closeFullPlayerToken) { _, token in
                if token != nil { showFullPlayer = false }
            }
            .alert(
                String(localized: "Podcast unavailable"),
                isPresented: $showFeedUnavailable
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "This episode is not linked to a subscribed podcast."))
            }
            .alert(
                String(localized: "Copied"),
                isPresented: $showCopiedAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedAlertMessage)
            }
            .confirmationDialog(
                "Remove from queue?",
                isPresented: Binding(
                    get: { episodePendingRemoveFromQueue != nil },
                    set: { if !$0 { episodePendingRemoveFromQueue = nil } }
                ),
                titleVisibility: .visible,
                presenting: episodePendingRemoveFromQueue
            ) { episode in
                Button("Remove from queue", role: .destructive) {
                    store.removeFromQueue(episode)
                    episodePendingRemoveFromQueue = nil
                }
                Button("Cancel", role: .cancel) {
                    episodePendingRemoveFromQueue = nil
                }
            } message: { episode in
                Text(
                    "Remove \"\(episode.title)\" from the queue? Removes from the queue only. Does not delete the download, mark played, or stop playback."
                )
            }
            .confirmationDialog(
                "Delete download?",
                isPresented: Binding(
                    get: { episodePendingDeleteDownload != nil },
                    set: { if !$0 { episodePendingDeleteDownload = nil } }
                ),
                titleVisibility: .visible,
                presenting: episodePendingDeleteDownload
            ) { episode in
                Button("Delete download", role: .destructive) {
                    downloads.delete(episode)
                    episodePendingDeleteDownload = nil
                }
                Button("Cancel", role: .cancel) {
                    episodePendingDeleteDownload = nil
                }
            } message: { episode in
                Text(
                    "Delete download for \"\(episode.title)\"? Removes the local offline file only. Keeps played status, queue, and favorites."
                )
            }
            .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
            .sheet(isPresented: $showCustomSleepTimer) {
                CustomSleepTimerSheet(initialMinutes: settings.lastCustomSleepTimerMinutes)
                    .environmentObject(playback)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showCustomPlaybackSpeed) {
                CustomPlaybackSpeedSheet(mode: .session, initialSpeed: playback.rate)
                    .environmentObject(playback)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showBookmarks) {
                EpisodeBookmarksSheet(episodeId: episode.id)
                    .environmentObject(playback)
                    .environmentObject(store)
            }
            .onChange(of: episode.id) { _, _ in
                // Same as Full Player: do not keep these sheets across an episode change.
                showBookmarks = false
                showEpisodePrivateNote = false
                showJumpToPosition = false
                // Shownotes (and Play soundbite inside) follow the live episode id.
                // Leaving the sheet open after auto-next retargets copy/share/soundbite
                // onto the next episode — Full Player already dismisses Description.
                showDescription = false
                // Delete-download / Remove-from-queue confirms keep the episode they were opened for.
                // Leaving them up after auto-next lets Confirm mutate that prior episode while the
                // mini player already shows the next one.
                episodePendingDeleteDownload = nil
                episodePendingRemoveFromQueue = nil
                // Speed sheet keeps the typed speed and Set applies it to whatever is now playing.
                showCustomPlaybackSpeed = false
                // Custom sleep sheet keeps the typed minutes and Set arms whatever is now playing.
                showCustomSleepTimer = false
                // Chapters sheet lists the live episode and tap seeks the player.
                // Leaving it open after auto-next shows the next episode's chapters
                // and a tap seeks that episode.
                showChapters = false
                // Transcript sheet lists the live episode and a cue tap seeks the player.
                // Leaving it open after auto-next reloads the next episode's cues
                // and a tap seeks that episode.
                showTranscript = false
            }
            .sheet(isPresented: $showEpisodePrivateNote) {
                EpisodePrivateNoteSheet(episodeId: episode.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showChapters) {
                // Prefer store episode (post-refresh) — same already-on-episode chapters as mini prev/next.
                // EpisodeChaptersSheet does not lazy-fetch remote/media chapters.
                EpisodeChaptersSheet(
                    chapters: chapters,
                    episode: store.episode(id: episode.id) ?? episode
                )
                .environmentObject(playback)
                .environmentObject(store)
                .environmentObject(settings)
            }
            .alert(
                String(localized: "Bookmark limit reached"),
                isPresented: $showAtCapAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "This episode already has 50 bookmarks. Delete one to add another."))
            }
            .sensoryFeedback(.success, trigger: bookmarkAddedTick)
            .sheet(isPresented: $showJumpToPosition) {
                JumpToPositionSheet(initialSeconds: playback.positionSeconds)
                    .environmentObject(playback)
            }
            .sheet(isPresented: $showDescription) {
                // Prefer store episode (post-refresh) over a possibly stale player copy — same as Full.
                EpisodeDescriptionSheetView(
                    episode: store.episode(id: episode.id) ?? episode,
                    feedTitle: feedForCurrentEpisode.map { store.displayTitle(for: $0) }
                )
            }
            .sheet(isPresented: $showTranscript) {
                // Prefer store episode (post-refresh) — same gate/path as Full TranscriptSheetView.
                TranscriptSheetView(episode: store.episode(id: episode.id) ?? episode)
                    .environmentObject(playback)
            }
        } else if let restored = playback.restoredEpisodeIfStillValid {
            restoredEpisodeBar(restored)
        } else {
            Button {
                showFullPlayer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Nothing playing"))
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "Start an episode from Inbox, Queue, or a feed."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Nothing playing"))
            .accessibilityValue(String(localized: "No episode is currently loaded"))
            .accessibilityHint(
                String(localized: "Start an episode from Inbox, Queue, or a feed to use the player controls.")
            )
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
            .onChange(of: subscribeLink.closeFullPlayerToken) { _, token in
                if token != nil { showFullPlayer = false }
            }
        }
    }

    /// Same cap gate as `EpisodeBookmarksSheet.canAdd` (minus note UI): current episode + finite position + under 50.
    private var canAddBookmark: Bool {
        guard let episode = playback.currentEpisode else { return false }
        return playback.positionSeconds.isFinite
            && playback.positionSeconds >= 0
            && !store.isBookmarkCapReached(for: episode.id)
    }

    private var addBookmarkAccessibilityHint: String {
        if let episode = playback.currentEpisode, store.isBookmarkCapReached(for: episode.id) {
            return String(localized: "Limit reached — delete a bookmark first")
        }
        return String(localized: "Saves the current playback position as a bookmark")
    }

    private func bookmarksAccessibilityValue(for episodeId: String) -> String {
        let count = store.bookmarkCount(for: episodeId)
        if count == 0 {
            return String(localized: "No bookmarks")
        }
        return String(localized: "\(count) bookmarks")
    }

    /// One-tap Add from mini ⋯ — empty note; same `PodcastStore.addBookmark` / 50-cap as Full sheet.
    private func addBookmarkFromMini() {
        guard let episode = playback.currentEpisode else { return }
        if store.isBookmarkCapReached(for: episode.id) {
            showAtCapAlert = true
            return
        }
        let position = playback.positionSeconds
        guard position.isFinite, position >= 0 else { return }
        let ok = store.addBookmark(
            episodeId: episode.id,
            positionSeconds: position,
            note: ""
        )
        if ok {
            bookmarkAddedTick += 1
        } else {
            showAtCapAlert = true
        }
    }

    /// Same gate as FullPlayerView: known finite duration and a current episode.
    private var canJumpToPosition: Bool {
        playback.currentEpisode != nil
            && playback.durationSeconds.isFinite
            && playback.durationSeconds > 0
    }

    /// Chapters already on the store/player episode (PSC / persisted Podcast Index / media).
    /// Mini player does not fetch remote or media chapters — Full Player does that lazily.
    private var chapters: [PodcastChapter] {
        guard let episode = playback.currentEpisode else { return [] }
        let resolved = store.episode(id: episode.id) ?? episode
        return resolved.chapters
    }

    /// Same gate as Full `chapterSkipControls`: hide Previous/Next when no chapters known on mini.
    private var canSkipChapters: Bool { !chapters.isEmpty }

    /// AntennaPod-like Previous target via `ChapterIndexing.previousSeekSeconds` (restart if >2s in).
    private var previousChapterTarget: Double? {
        ChapterIndexing.previousSeekSeconds(in: chapters, at: playback.positionSeconds)
    }

    /// Next chapter start via `ChapterIndexing.nextSeekSeconds`, or `nil` on the last chapter.
    private var nextChapterTarget: Double? {
        ChapterIndexing.nextSeekSeconds(in: chapters, at: playback.positionSeconds)
    }

    private var nextChapterAccessibilityHint: String {
        if let target = nextChapterTarget {
            let duration = playback.durationSeconds
            if duration.isFinite, duration > 0, target >= duration {
                return String(localized: "Finishes the episode the same way as a forward skip.")
            }
        }
        return String(localized: "Seeks to the next chapter")
    }


    /// Title of the chapter at `positionSeconds`, or `nil` when none / empty title.
    private var currentChapterTitle: String? {
        guard let index = ChapterIndexing.currentIndex(in: chapters, at: playback.positionSeconds) else {
            return nil
        }
        let title = chapters[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func openFullPlayerAccessibilityLabel(for episode: PodcastEpisode) -> String {
        if let chapter = currentChapterTitle {
            return String(localized: "Open full player, \(episode.title), chapter \(chapter)")
        }
        return String(localized: "Open full player, \(episode.title)")
    }

    private var feedForCurrentEpisode: PodcastFeed? {
        guard let episode = playback.currentEpisode else { return nil }
        return store.feed(containingEpisodeId: episode.id)
    }

    private func openPodcastFromMiniPlayer() {
        guard let feed = feedForCurrentEpisode else {
            showFeedUnavailable = true
            return
        }
        // Close full player sheet if open, then navigate.
        showFullPlayer = false
        let id = feed.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NewEpisodeNotificationCoordinator.deepLink.openFeed(id: id)
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            if playback.isSleepTimerActive {
                if let label = playback.sleepTimerStatusLabel {
                    Text(String(format: String(localized: "Active · %@"), label))
                }
                Button(extendSleepTimerButtonTitle(minutes: 5)) {
                    playback.extendSleepTimer(byMinutes: 5)
                }
                .accessibilityLabel(extendSleepTimerButtonTitle(minutes: 5))
                .accessibilityHint(extendSleepTimerAccessibilityHint(minutes: 5))
                Button(extendSleepTimerButtonTitle(minutes: 10)) {
                    playback.extendSleepTimer(byMinutes: 10)
                }
                .accessibilityLabel(extendSleepTimerButtonTitle(minutes: 10))
                .accessibilityHint(extendSleepTimerAccessibilityHint(minutes: 10))
                Button("Turn off", role: .destructive) {
                    playback.disableSleepTimer()
                }
                Divider()
            }
            ForEach(PlaybackService.clockPresetsMinutes, id: \.self) { minutes in
                Button("\(minutes) min") {
                    playback.setSleepTimer(minutes: minutes)
                }
            }
            Button("End of episode") {
                playback.setSleepTimerEndOfEpisode()
            }
            Button(String(localized: "End of chapter")) {
                playback.setSleepTimerEndOfChapter()
            }
            .disabled(!canSleepTimerEndOfChapter)
            .accessibilityHint(
                canSleepTimerEndOfChapter
                    ? String(localized: "Pauses when the current chapter ends")
                    : String(localized: "No chapters available")
            )
            Button(String(localized: "End of queue")) {
                playback.setSleepTimerEndOfQueue()
            }
            .disabled(!canSleepTimerEndOfQueue)
            .accessibilityHint(
                canSleepTimerEndOfQueue
                    ? String(localized: "Stops after the last episode in the queue")
                    : sleepTimerEndOfQueueDisabledHint
            )
            Button(String(localized: "Custom…")) {
                showCustomSleepTimer = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                if playback.isSleepTimerActive, let label = playback.sleepTimerStatusLabel {
                    Text(label)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                }
            }
        }
        .accessibilityLabel(playback.sleepTimerAccessibilityLabel)
        .accessibilityHint(String(localized: "Sets or turns off the sleep timer"))
    }

    /// Extend only lengthens an active **clock** timer. On End of episode / chapter / queue it
    /// replaces that mode with a new clock countdown (`PlaybackService.extendSleepTimer`).
    private func extendSleepTimerButtonTitle(minutes: Int) -> String {
        switch playback.sleepTimerMode {
        case .clock:
            return String(localized: "Extend +\(minutes) min")
        case .endOfEpisode, .endOfChapter, .endOfQueue:
            return String(localized: "Switch to \(minutes) min clock")
        case nil:
            return String(localized: "Extend +\(minutes) min")
        }
    }

    private func extendSleepTimerAccessibilityHint(minutes: Int) -> String {
        switch playback.sleepTimerMode {
        case .clock:
            return String(localized: "Adds \(minutes) minutes to the remaining clock sleep timer.")
        case .endOfEpisode, .endOfChapter, .endOfQueue:
            return String(localized: "Replaces End of episode, End of chapter, or End of queue with a \(minutes)-minute clock sleep timer.")
        case nil:
            return String(localized: "Sets a \(minutes)-minute clock sleep timer.")
        }
    }

    /// Chapters already on the store/player episode — same source as mini chapter title.
    /// Disabled until ≥1 chapter is known (Full Player may lazy-load and persist later).
    private var canSleepTimerEndOfChapter: Bool {
        !chapters.isEmpty
    }

    /// EOQ needs a following Queue item via `nextQueueEpisode` (head when current not queued).
    /// Disabled when the Queue is empty or the playing episode is already last (nothing left to drain).
    private var canSleepTimerEndOfQueue: Bool {
        guard let id = playback.currentEpisode?.id else { return false }
        return store.nextQueueEpisode(after: id) != nil
    }
    private var sleepTimerEndOfQueueDisabledHint: String {
        if store.queue.isEmpty {
            return String(localized: "Queue is empty")
        }
        return String(localized: "No further episodes in the queue")
    }


    private var sourceIndicator: some View {
        Label(
            playback.isPlayingFromLocalFile ? String(localized: "Local") : String(localized: "Stream"),
            systemImage: playback.isPlayingFromLocalFile ? "internaldrive" : "wifi"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(playback.isPlayingFromLocalFile ? String(localized: "Playing from download") : String(localized: "Streaming"))
    }

    private var timeLabel: String {
        "\(format(playback.positionSeconds)) / \(rightTimeLabel)"
    }

    /// Duration, or −remaining when Settings → Show remaining time is on.
    /// When Remaining time respects speed is on, −remaining ÷ live session rate
    /// (fallback feed/default, 0.5…3.0); otherwise wall-clock.
    private var rightTimeLabel: String {
        // Unknown duration (live stream, item still loading): no 0:00 / -0:00 end time.
        guard playback.durationSeconds.isFinite, playback.durationSeconds > 0 else { return "--:--" }
        if settings.showRemainingTime {
            let wall = playback.durationSeconds - playback.positionSeconds
            let fallback: Float
            if let episode = playback.currentEpisode {
                fallback = store.resolvedPlaybackSpeedForRemaining(for: episode)
            } else {
                fallback = max(
                    EpisodeRemainingTime.minimumPlaybackSpeedDivisor,
                    settings.defaultPlaybackSpeed
                )
            }
            let display = EpisodeRemainingTime.playerChromeRemainingSeconds(
                wallClockSeconds: wall,
                respectsSpeed: settings.remainingTimeRespectsSpeed,
                sessionRate: playback.rate,
                fallbackSpeed: fallback
            )
            return formatRemaining(display)
        }
        return format(playback.durationSeconds)
    }


    /// Cold-launch restored placeholder. Caption says Continue listening only when saved
    /// progress is past 1 second (same threshold as Home Continue); otherwise Previous episode.
    @ViewBuilder
    private func restoredEpisodeBar(_ restored: PodcastEpisode) -> some View {
        let restoredPosition = store.positionSeconds(for: restored.id)
        let restoredHasContinueProgress = restoredPosition > 1
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(restored.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(
                    restoredHasContinueProgress
                        ? String(localized: "Continue listening") + " · " + format(restoredPosition)
                        : String(localized: "Previous episode")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button {
                playback.playRestoredEpisode()
            } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Play"))
            .accessibilityHint(
                restoredHasContinueProgress
                    ? String(localized: "Resumes this episode from the saved position")
                    : String(localized: "Starts this episode from the beginning")
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Same clock as the full player. Minutes-only (`125:05`) hid the hour,
    /// so a two-hour episode did not match the full-player `2:05:05`.
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
