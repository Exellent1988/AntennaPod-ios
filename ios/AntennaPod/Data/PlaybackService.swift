import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

/// Clock / end-of-episode / end-of-chapter / end-of-queue sleep timer modes for beta (AntennaPod P0 basis).
enum SleepTimerMode: Equatable {
    case clock(minutes: Int)
    case endOfEpisode
    /// Pause when playback reaches the end of the chapter active at activation
    /// (next chapter start, or episode end for the last chapter when duration is known).
    case endOfChapter
    /// Advance through Queue via `nextQueueEpisode` until empty / play fails, then stop (no Same-podcast / Off fallback).
    case endOfQueue
}

@MainActor
final class PlaybackService: ObservableObject {
    /// Fallback when settings unbound (AntennaPod `prefSmartMarkAsPlayedSecs` default = 30).
    static let defaultSmartMarkAsPlayedSeconds: Double = 30
    /// Throttle JSON writes while the periodic observer fires every 0.5s.
    private static let persistIntervalSeconds: Double = 5
    /// Soft fade window matching Android `SleepTimer.NOTIFICATION_THRESHOLD` (10s). Clock only.
    static let fadeThresholdSeconds: Double = 10

    static let clockPresetsMinutes: [Int] = [5, 10, 15, 30, 45, 60]
    /// Custom sleep timer UI range (minutes). Presets stay 5–60; fade unchanged.
    static let customSleepTimerMinutesRange: ClosedRange<Int> = 1...180
    /// Custom playback speed UI / clamp range for stock `AVPlayer.rate`.
    /// Honest: with **Preserve pitch** on (default), quality is typically best ~0.5–2.0; 2.0–3.0 is allowed
    /// (AntennaPod-like) but may sound worse. Off → pitch scales with rate (chipmunks). Not Android ExoPlayer.
    static let customPlaybackSpeedRange: ClosedRange<Float> = 0.5...3.0
    /// Step for Custom… sheet (Slider / Stepper).
    static let customPlaybackSpeedStep: Float = 0.05

    /// Custom rewind / fast-forward skip interval range (seconds). Presets stay 5/10/15/20/30/60.
    static let customSkipIntervalSecondsRange: ClosedRange<Int> = 5...60
    /// Custom smart-mark threshold range (seconds). Presets stay Off/15/30/60/120/300/600 (Android).
    /// Off (0) is Settings-only; Custom… uses 1…600.
    static let customSmartMarkAsPlayedSecondsRange: ClosedRange<Int> = 1...600

    /// Clamp + snap to `customPlaybackSpeedStep` within `customPlaybackSpeedRange`.
    static func clampPlaybackSpeed(_ rate: Float) -> Float {
        let lo = customPlaybackSpeedRange.lowerBound
        let hi = customPlaybackSpeedRange.upperBound
        let clamped = min(max(rate, lo), hi)
        let stepped = (clamped / customPlaybackSpeedStep).rounded() * customPlaybackSpeedStep
        return min(max(stepped, lo), hi)
    }

    /// Display label: one decimal when on a 0.1 grid, else two (e.g. 1.25×).
    static func formatPlaybackSpeed(_ rate: Float) -> String {
        let snapped = clampPlaybackSpeed(rate)
        let tenths = snapped * 10
        if abs(tenths - tenths.rounded()) < 0.001 {
            return String(format: "%.1f×", snapped)
        }
        return String(format: "%.2f×", snapped)
    }

    /// Throttle lock-screen elapsed updates (system interpolates via rate + timestamp).
    private static let nowPlayingUpdateIntervalSeconds: Double = 5

    @Published var currentEpisode: PodcastEpisode? {
        didSet {
            if let id = currentEpisode?.id {
                // A loaded episode replaces the cold-launch placeholder.
                restoredEpisode = nil
                if oldValue?.id != id {
                    UserDefaults.standard.set(id, forKey: Self.lastEpisodeIdKey)
                }
            } else if oldValue != nil {
                // Player unloaded (ended with nothing next, stop, backup import): nothing to restore.
                UserDefaults.standard.removeObject(forKey: Self.lastEpisodeIdKey)
            }
        }
    }

    /// UserDefaults key: id of the loaded episode, kept across launches for a paused restore.
    static let lastEpisodeIdKey = "playback.lastEpisodeId"

    /// Episode loaded when the previous run ended, shown paused in the mini player after a cold
    /// launch. Only a placeholder: no AVPlayer, no audio session, no Now Playing. `currentEpisode`
    /// stays nil until Play, which goes through `play(episode:)`.
    @Published private(set) var restoredEpisode: PodcastEpisode?

    @Published var isPlaying = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0

    /// Remaining seconds when a clock timer is active; `nil` when inactive or end-of-episode mode.
    @Published private(set) var sleepTimerRemainingSeconds: Double?
    @Published private(set) var sleepTimerMode: SleepTimerMode?
    @Published private(set) var isSleepTimerActive = false
    /// `true` when the current AVPlayer item is a local file URL (offline); `false` when streaming.
    @Published private(set) var isPlayingFromLocalFile = false
    /// Honest error for stream Wi‑Fi-only refusal (UI alert); cleared on successful play.
    @Published var lastError: String?

    static var streamCellularBlockedMessage: String {
        String(localized: "Streaming is Wi‑Fi only. Connect to Wi‑Fi or Ethernet, play a downloaded episode, or turn off Stream Wi‑Fi only in Settings → Network / Downloads.")
    }

    /// Bound from the app for progress / played / continuous advance (Queue or Same podcast).
    weak var store: PodcastStore?
    /// Bound so continuous playback prefers offline files when present.
    weak var downloads: DownloadService?
    /// Bound for default playback speed on new episode starts.
    weak var settings: AppSettings?

    /// Rewind interval from Settings (AntennaPod default 10s).
    var rewindSeconds: Double {
        Double(settings?.rewindSeconds ?? AppSettings.defaultRewindSeconds)
    }

    /// Fast-forward interval from Settings (AntennaPod default 30s).
    var fastForwardSeconds: Double {
        Double(settings?.fastForwardSeconds ?? AppSettings.defaultFastForwardSeconds)
    }

    private var player: AVPlayer?
    /// Shared player for the full-player video surface (`AVPlayerLayer` / `EpisodeVideoSurface`).
    /// Nil when nothing is loaded. Lockscreen / Now Playing stays metadata-only (no video).
    var avPlayer: AVPlayer? { player }
    /// Picture-in-Picture for the video surface (beta lite). Lives here so PiP can outlive the full-player sheet.
    let pictureInPicture = PictureInPictureSession()
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
    /// First finite item duration only. Later jitter stays on the throttled tick.
    private var durationCancellable: AnyCancellable?
    /// True after this loaded item's first finite duration was written to Now Playing.
    private var didWriteLoadedItemDuration = false
    private var pipCancellable: AnyCancellable?
    /// Re-applies video-track enable/disable when `AVPlayerItem.tracks` populates after ready.
    private var videoTrackPolicyCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    /// Item load failure (offline, dead host) and mid-episode network loss. A failed
    /// `AVPlayerItem` never plays again, so these surface the error and force a rebuild.
    private var itemStatusCancellable: AnyCancellable?
    private var failedToEndObserver: NSObjectProtocol?
    private var lastPersistedAt: Date = .distantPast
    /// Monotonic seek id. Not reset on teardown, so a late completion cannot
    /// release a newer episode's hold (tokens would otherwise collide at 1).
    private var seekHoldToken = 0
    /// Non-nil while the latest `AVPlayer.seek` has not finished. Periodic samples
    /// must not persist that pre-seek playhead (often ~0 on resume) over `playback.json`.
    private var activeSeekHold: Int?

    private var sleepTimerEndDate: Date?
    private var sleepTimerPausedRemaining: Double?
    private var sleepTimerDidFade = false
    private var sleepVolume: Float = 1.0
    /// Wall-clock chapter end (seconds) snapped when end-of-chapter mode can resolve a boundary.
    /// `nil` until chapters (and last-chapter duration if needed) are known — then locked.
    private var sleepTimerChapterEndSeconds: Double?

    private var remoteCommandsConfigured = false
    private var audioSessionObserversConfigured = false
    /// Set on interruption began when we were playing; honored on ended + shouldResume.
    private var resumeAfterInterruption = false
    private var lastNowPlayingUpdateAt: Date = .distantPast
    private var cachedArtworkURL: String?
    private var cachedArtwork: MPMediaItemArtwork?

    /// Skip-intro applied once for this play session (fresh start only).
    private var didApplySkipIntroForSession = false
    /// Skip-outro fired once per episode play session (avoids observer re-entry / loops).
    private var didTriggerSkipOutroForSession = false
    /// When the current item was paused (user / audio-session / sleep-timer). `nil` means no rewind-after-pause.
    private var pausedAt: Date?

    /// Episode id whose mark-played reset must survive later progress ticks.
    /// `markPlayed` zeros `playback.json` without moving the live playhead; the
    /// periodic observer and pause would otherwise write that playhead back.
    /// Cleared when this episode is started again, marked played with reset
    /// off, or the listener seeks. Mark unplayed leaves it, so the next
    /// progress tick cannot restore the live playhead. Automatic rewind does not clear it.
    private var markPlayedResetHoldEpisodeId: String?

    /// Loaded episode the listener explicitly marked unplayed. Leaving it inside the
    /// smart-mark window must not mark it played again. Cleared when a new play
    /// session starts; playing to the actual end still marks played.
    private var smartMarkSuppressedEpisodeId: String?

    /// Wall-clock end (seconds) for feed `podcast:soundbite` play-until-end.
    /// When set and playing, auto-pause at this position (like user pause — no queue advance).
    /// Cleared on user seek/skip/pause, episode change, sleep-timer fire, or when the end is reached.
    /// Not a separate clip player — same AVPlayer / episode progress.
    private var soundbiteEndSeconds: Double?

    init() {
        setupRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        pipCancellable = pictureInPicture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Same episode already has a player. Rebuilding would drop up to the 5s
    /// progress save and, when the saved position is still ~0, run skip intro again.
    /// A list Play / Downloads Play on that episode keeps the player: pause resumes
    /// in place (rewind after pause included). Play from beginning, an alternate
    /// media URL, and an explicit local file while this session is still streaming
    /// still rebuild.
    private func shouldKeepLoadedPlayer(
        episode: PodcastEpisode,
        fileURL: URL?,
        preferredMediaURL: URL?,
        fromBeginning: Bool
    ) -> Bool {
        guard !fromBeginning, preferredMediaURL == nil else { return false }
        guard currentEpisode?.id == episode.id, player != nil else { return false }
        // A failed item (stream lost the network) cannot resume; rebuild from the saved position.
        if player?.currentItem?.status == .failed {
            return false
        }
        if fileURL != nil, !isPlayingFromLocalFile {
            return false
        }
        // Delete removes the file but leaves this player. A missing local file must
        // rebuild so resolvePlaybackURL can stream. A file that is still there keeps it.
        if isPlayingFromLocalFile,
           let asset = player?.currentItem?.asset as? AVURLAsset,
           asset.url.isFileURL,
           !FileManager.default.fileExists(atPath: asset.url.path) {
            return false
        }
        return true
    }

    /// The loaded `AVPlayerItem` failed (stream could not load or lost the network). AVPlayer
    /// never plays such an item again; callers rebuild through `play(episode:)` instead.
    private var hasFailedItem: Bool {
        player?.currentItem?.status == .failed
    }

    /// Starts or switches playback. Returns `false` when streaming is blocked by Wi‑Fi-only policy
    /// (current player left unchanged; `lastError` set for UI).
    /// - Parameter fromBeginning: When `true`, start at position 0 (ignore saved resume) and do **not**
    ///   apply skip-intro — user asked for the literal start. Does not flip played/unplayed flags.
    /// - Parameter preferredMediaURL: Optional http(s) media URL override (e.g. `podcast:alternateEnclosure`
    ///   source). Same episode id / metadata / queue / favorites; AVPlayer uses this URL. Download cache
    ///   still keys on the primary enclosure — local file is reused only when that primary remote URL
    ///   matches `preferredMediaURL`. Non-http(s) URLs are rejected (return false). Video-as-audio,
    ///   HTTP proxy, and Wi‑Fi stream gates still apply.
    /// When this episode is already loaded, keeps that player instead of rebuilding it.
    @discardableResult
    func play(
        episode: PodcastEpisode,
        fileURL: URL? = nil,
        preferredMediaURL: URL? = nil,
        fromBeginning: Bool = false
    ) -> Bool {
        if shouldKeepLoadedPlayer(
            episode: episode,
            fileURL: fileURL,
            preferredMediaURL: preferredMediaURL,
            fromBeginning: fromBeginning
        ) {
            // Same gate as a fresh stream start, and still before any teardown:
            // cellular + Wi‑Fi-only refuses without stopping audio that is already going.
            if !isPlayingFromLocalFile, settings?.streamWifiOnly == true {
                AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
                if !NetworkPathGate.shared.allowsTransfer(wifiOnly: true) {
                    lastError = Self.streamCellularBlockedMessage
                    return false
                }
            }
            lastError = nil
            // Rebuild used to drop a pending soundbite end window. Do that here
            // only after a Wi-Fi refusal (a blocked resume must not clear it or
            // stop audio) and before resume, without seeking or rebuilding.
            clearSoundbiteEndMarker()
            if isPlaying {
                return true
            }
            togglePlayPause()
            store?.touchLastPlayed(episode.id)
            store?.publishWidgetSnapshot()
            return true
        }
        guard let url = resolvePlaybackURL(
            for: episode,
            preferredFileURL: fileURL,
            preferredMediaURL: preferredMediaURL
        ) else {
            return false
        }
        let playingLocal = url.isFileURL
        if !playingLocal, settings?.streamWifiOnly == true {
            AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
            if !NetworkPathGate.shared.allowsTransfer(wifiOnly: true) {
                lastError = Self.streamCellularBlockedMessage
                return false
            }
        }
        lastError = nil
        // New play / episode switch replaces any pending soundbite end window.
        clearSoundbiteEndMarker()

        let isFreshEpisode = currentEpisode?.id != episode.id
        var leavingEpisodeId: String?
        if let current = currentEpisode, current.id != episode.id {
            leavingEpisodeId = current.id
            finishCurrentEpisode(ended: false)
        }
        // New play session. finishCurrentEpisode already persisted a mark-played
        // reset for the episode we left; this start may save its own progress.
        markPlayedResetHoldEpisodeId = nil
        smartMarkSuppressedEpisodeId = nil

        // Fresh episode (or first play): effective speed = feed override ?? Settings default.
        // Session rate from player tap/Custom… is intentionally replaced on episode change
        // (same spirit as Android temporary speed scoped to the playing item). Feed settings
        // own the persistent override; player controls never write FeedSettings.playbackSpeed.
        if isFreshEpisode {
            rate = Self.clampPlaybackSpeed(resolvedPlaybackSpeed(for: episode))
        }

        // Keep an active sleep timer across episode changes (clock continues; EOE/EOC/EOQ stay armed).
        // Choose the resume point while this episode is still loaded. Saved progress
        // can lag the live playhead by about 5s. A rewind that is not saved yet must
        // not jump forward. A different episode still uses the stored position.
        let resumeAt: Double
        if fromBeginning {
            resumeAt = 0
        } else if currentEpisode?.id == episode.id, player != nil, positionSeconds.isFinite {
            resumeAt = max(0, positionSeconds)
        } else {
            resumeAt = resumePosition(for: episode.id)
        }
        tearDownPlayer(clearSleepTimer: false)
        // An armed end-of-chapter timer snapped its boundary in the episode we left.
        // Drop it so the next tick resolves the chapter end in the new episode.
        if isFreshEpisode {
            sleepTimerChapterEndSeconds = nil
        }
        currentEpisode = episode
        isPlayingFromLocalFile = playingLocal
        // Local file no longer the active player item — run deferred auto-delete if pending.
        if let leavingEpisodeId {
            store?.flushAutoDeleteAfterPlaying(for: leavingEpisodeId)
        }
        let item = AVPlayerItem(url: url)
        applyTimePitchAlgorithm(to: item)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.rate = rate
        // Sleep-timer fade uses player.volume (0…1). Soft boost (>100%) uses AVAudioMix on the item.
        newPlayer.volume = sleepVolume
        player = newPlayer
        applyVolumeBoost(to: item)
        applyVideoAsAudioOnlyPolicy(to: item)
        observe(player: newPlayer, item: item)

        // New play session for this episode item — reset intro/outro once-guards.
        didApplySkipIntroForSession = false
        didTriggerSkipOutroForSession = false
        // Cold play / episode (re)start is not a pause-resume — do not rewind-after-pause.
        pausedAt = nil

        if resumeAt > 1 {
            let time = CMTime(seconds: resumeAt, preferredTimescale: 600)
            let hold = beginSeekHold()
            newPlayer.seek(to: time) { [weak self] finished in
                Task { @MainActor in
                    guard let self else { return }
                    self.endSeekHold(hold)
                    guard finished, self.player === newPlayer else { return }
                    self.positionSeconds = resumeAt
                    self.persistProgress(force: true)
                    self.updateNowPlayingInfo(force: true)
                }
            }
            positionSeconds = resumeAt
        } else if fromBeginning {
            // Explicit play-from-beginning: absolute 0, no skip-intro.
            positionSeconds = 0
        } else {
            // Fresh start (position ≈ 0): skip intro once when configured (feed override else global).
            // Do not seek when that target is at/past a known duration or inside skip outro:
            // playback would sit at the end and checkSkipOutro / DidPlayToEndTime would mark
            // the episode played before any of it was heard.
            let intro = Double(resolvedSkipIntroSeconds(for: episode))
            if intro > 0, skipIntroSeekFits(episode: episode, intro: intro) {
                let time = CMTime(seconds: intro, preferredTimescale: 600)
                let hold = beginSeekHold()
                newPlayer.seek(to: time) { [weak self] finished in
                    Task { @MainActor in
                        guard let self else { return }
                        self.endSeekHold(hold)
                        guard finished, self.player === newPlayer else { return }
                        self.positionSeconds = intro
                        self.didApplySkipIntroForSession = true
                        self.persistProgress(force: true)
                        self.updateNowPlayingInfo(force: true)
                    }
                }
                positionSeconds = intro
                didApplySkipIntroForSession = true
            } else {
                positionSeconds = 0
            }
        }

        // AVPlayer.play() is equivalent to rate = 1.0 and would drop feed/default/session speed.
        newPlayer.play()
        newPlayer.rate = rate
        isPlaying = true
        activateSession()
        setupRemoteCommandsIfNeeded()
        resumeSleepTimerIfNeeded()
        updateNowPlayingInfo(force: true)
        loadArtworkIfNeeded()
        store?.touchLastPlayed(episode.id)
        store?.publishWidgetSnapshot()
        applyIdleTimerPolicy()
        return true
    }

    func togglePlayPause() {
        guard let player else {
            // Cold launch: the restored placeholder starts through the normal play path.
            if currentEpisode == nil, restoredEpisode != nil {
                playRestoredEpisode()
            }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
            // User pause clears pending soundbite end (same as seek/skip).
            clearSoundbiteEndMarker()
            // Pause only saves progress; smart-mark happens on leave/end (AntennaPod-like).
            persistProgress(force: true)
            pauseSleepTimerCountdown()
            // Cancel fade + restore volume so resume is not stuck at a faded level.
            cancelSleepTimerFade(restoreVolume: true)
            recordPausedAt()
        } else {
            // Play on a failed item did nothing and showed Pause with no audio. Rebuild instead.
            if player.currentItem?.status == .failed, let episode = currentEpisode {
                play(episode: episode)
                return
            }
            applyRewindAfterPauseIfNeeded()
            activateSession()
            player.play()
            player.rate = rate
            isPlaying = true
            resumeSleepTimerIfNeeded()
        }
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
    }

    /// Launch only, after feeds and playback states are loaded: show the previous run's episode
    /// paused when it still exists and is unplayed. Does not create a player or touch the session.
    func restoreLastEpisodeIfPossible() {
        guard currentEpisode == nil, restoredEpisode == nil else { return }
        guard let id = UserDefaults.standard.string(forKey: Self.lastEpisodeIdKey) else { return }
        guard let store, let episode = store.episode(id: id), !store.isPlayed(id) else {
            UserDefaults.standard.removeObject(forKey: Self.lastEpisodeIdKey)
            return
        }
        restoredEpisode = episode
    }

    /// Restored placeholder while it still exists and is unplayed (mark played, unsubscribe,
    /// or a refresh that drops it hide it). Uses the store copy so refreshed metadata applies.
    var restoredEpisodeIfStillValid: PodcastEpisode? {
        guard currentEpisode == nil, let restored = restoredEpisode, let store else { return nil }
        guard let live = store.episode(id: restored.id), !store.isPlayed(live.id) else { return nil }
        return live
    }

    /// Play the restored placeholder via `play(episode:)` (saved position, stream fallback for a
    /// deleted download, Stream Wi‑Fi only refusal). A refusal keeps the placeholder.
    @discardableResult
    func playRestoredEpisode() -> Bool {
        guard let episode = restoredEpisodeIfStillValid else {
            restoredEpisode = nil
            return false
        }
        return play(episode: episode)
    }

    /// Swap in refreshed episode metadata (title, enclosure, shownotes) for the loaded item.
    /// Same id only. Does not seek, change rate, or rebuild the `AVPlayer` item.
    func replaceCurrentEpisodeMetadata(with episode: PodcastEpisode) {
        guard currentEpisode?.id == episode.id, currentEpisode != episode else { return }
        currentEpisode = episode
        updateNowPlayingInfo(force: true)
        // Same id, new image URL. Unchanged URL returns immediately; a removed URL
        // clears the lock screen cover without a download.
        loadArtworkIfNeeded()
        store?.publishWidgetSnapshot()
    }

    func stop() {
        resumeAfterInterruption = false
        pausedAt = nil
        clearSoundbiteEndMarker()
        let leavingId = currentEpisode?.id
        finishCurrentEpisode(ended: false)
        tearDownPlayer(clearSleepTimer: true)
        deactivateSessionAfterPlaybackStopped()
        currentEpisode = nil
        isPlayingFromLocalFile = false
        isPlaying = false
        positionSeconds = 0
        durationSeconds = 0
        clearNowPlayingInfo()
        if let leavingId {
            store?.flushAutoDeleteAfterPlaying(for: leavingId)
        }
        store?.publishWidgetSnapshot()
        applyIdleTimerPolicy()
    }

    /// Unload the current episode without persisting progress, marking played,
    /// removing it from the queue, or deleting its download.
    /// Backup import replaces `playback.json`; a later progress tick must not
    /// write the pre-import position back, and the mini player / Lock Screen
    /// must not keep an episode from the previous catalog.
    func discardLoadedEpisodeForBackupImport() {
        resumeAfterInterruption = false
        pausedAt = nil
        clearSoundbiteEndMarker()
        tearDownPlayer(clearSleepTimer: true)
        currentEpisode = nil
        isPlayingFromLocalFile = false
        isPlaying = false
        positionSeconds = 0
        durationSeconds = 0
        clearNowPlayingInfo()
        applyIdleTimerPolicy()
    }

    func setRate(_ newRate: Float) {
        let clamped = Self.clampPlaybackSpeed(newRate)
        rate = clamped
        if isPlaying {
            player?.rate = clamped
        }
        updateNowPlayingInfo(force: true)
    }

    /// Android `SpeedPresetChangedEvent`: when per-feed playback speed changes for the feed of
    /// the current episode, apply effective speed (feed override ?? global default).
    /// Player tap/long-press still only call `setRate` (session) — they do **not** rewrite feed speed.
    func applyEffectivePlaybackSpeedIfCurrent(feedId: UUID) {
        guard let episode = currentEpisode,
              let store,
              let feed = store.feed(containingEpisodeId: episode.id),
              feed.id == feedId else { return }
        setRate(resolvedPlaybackSpeed(for: episode))
    }

    /// Custom title is the Now Playing artist. The progress tick is throttled and
    /// does not run while paused, so a rename must refresh the loaded episode now.
    /// Does not change the rate, seek, or publish the widget snapshot.
    func refreshNowPlayingTitleIfCurrent(feedId: UUID) {
        guard let episode = currentEpisode,
              let store,
              let feed = store.feed(containingEpisodeId: episode.id),
              feed.id == feedId else { return }
        updateNowPlayingInfo(force: true)
    }

    /// AntennaPod-style: advance session rate to the next `AppSettings.speedPresets` value (wraps).
    /// If the current rate is not a preset, jumps to the first preset (same as Android `setNextPlaybackSpeed`).
    /// Match with a small tolerance: `clampPlaybackSpeed` snaps 1.3 in Float so
    /// `1.3 / 0.05` is 25.999998 and the stored rate is not bit-identical to the
    /// preset literal. Exact equality then wraps a visible 1.3× tap to 0.8×.
    func cycleToNextSpeedPreset() {
        let presets = AppSettings.speedPresets
        guard !presets.isEmpty else { return }
        let idx = presets.firstIndex { abs($0 - rate) < 0.001 }
        if let idx {
            let next = idx + 1
            setRate(next < presets.count ? presets[next] : presets[0])
        } else {
            setRate(presets[0])
        }
    }

    func seek(bySeconds delta: Double) {
        // Android seekForward: a skip that would land at or past a known duration
        // finishes the episode (mark played, continuous next, sleep-timer end).
        // Seeking only to the last second never posts DidPlayToEndTime, so the
        // playhead sits on the end, the episode stays unplayed, and the queue
        // does not advance. Rewind and the scrubber still use seek(toSeconds:).
        if delta > 0,
           player != nil,
           durationSeconds.isFinite,
           durationSeconds > 0,
           positionSeconds + delta >= durationSeconds {
            activeSeekHold = nil
            positionSeconds = durationSeconds
            handlePlaybackEnded()
            return
        }
        seek(toSeconds: positionSeconds + delta)
    }

    /// Typed Jump to position. A target at or past a known duration finishes
    /// like a forward skip. A time inside the episode still seeks. Unknown or
    /// zero duration does not finish. The scrubber stays on `seek(toSeconds:)`.
    func jumpToPosition(seconds: Double) {
        if player != nil,
           durationSeconds.isFinite,
           durationSeconds > 0,
           seconds >= durationSeconds {
            activeSeekHold = nil
            positionSeconds = durationSeconds
            handlePlaybackEnded()
            return
        }
        seek(toSeconds: max(0, seconds))
    }

    /// Absolute seek for scrubber / Now Playing / chapter / soundbite start.
    /// - Parameter clearSoundbiteEndMarker: When `true` (default), cancels a pending soundbite
    ///   play-until-end window (user scrub / skip / chapter). Pass `false` when `playSoundbite`
    ///   seeks to the clip start before arming the end marker.
    /// - Parameter resnapsSleepTimerChapterEnd: When `true` (default), an armed end-of-chapter timer
    ///   picks the chapter at the seek target. Automatic rewind-after-pause passes `false`.
    func seek(
        toSeconds seconds: Double,
        clearSoundbiteEndMarker clearEnd: Bool = true,
        releasesMarkPlayedResetHold: Bool = true,
        resnapsSleepTimerChapterEnd: Bool = true
    ) {
        guard let player else {
            return
        }
        // User seek cancels an in-progress sleep fade and restores pre-fade volume.
        cancelSleepTimerFade(restoreVolume: true)
        if releasesMarkPlayedResetHold {
            markPlayedResetHoldEpisodeId = nil
        }
        if clearEnd {
            clearSoundbiteEndMarker()
        }
        let target = max(0, seconds)
        let capped: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            capped = min(target, durationSeconds)
        } else {
            capped = target
        }
        let time = CMTime(seconds: capped, preferredTimescale: 600)
        let hold = beginSeekHold()
        let seekingPlayer = player
        seekingPlayer.seek(to: time) { [weak self] _ in
            Task { @MainActor in
                self?.endSeekHold(hold)
            }
        }
        positionSeconds = capped
        // A seek into another chapter must not keep the old boundary: a later one
        // paused right after a forward chapter jump, an earlier one ran past the chapter.
        if resnapsSleepTimerChapterEnd, isSleepTimerActive, case .endOfChapter = sleepTimerMode {
            sleepTimerChapterEndSeconds = nil
            refreshSleepTimerChapterEndTarget()
        }
        persistProgress(force: true)
        updateNowPlayingInfo(force: true)
    }

    /// Restart the **currently loaded** episode at position 0 and continue/start playback.
    /// If already playing → seek to 0 and keep playing. If paused → seek to 0 and play.
    /// Progress is persisted via `seek` / `saveProgress` only — does **not** flip played/unplayed.
    func playFromBeginning() {
        guard let episode = currentEpisode, player != nil else { return }
        // Seek + play on a failed item (stream lost the network) is silent and showed Pause
        // with no audio. Rebuild at 0 instead (`fromBeginning` skips resume / skip-intro).
        if hasFailedItem {
            play(episode: episode, fromBeginning: true)
            return
        }
        seek(toSeconds: 0)
        // Intentional restart — do not apply rewind-after-pause on the ensuing play.
        pausedAt = nil
        guard let player, !isPlaying else { return }
        activateSession()
        player.play()
        player.rate = rate
        isPlaying = true
        resumeSleepTimerIfNeeded()
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
    }

    /// Load/start `episode` at position 0 and play. If it is already the current item, seeks in place
    /// (no player teardown). Otherwise uses `play(..., fromBeginning: true)`.
    @discardableResult
    func playFromBeginning(episode: PodcastEpisode, fileURL: URL? = nil) -> Bool {
        if currentEpisode?.id == episode.id, player != nil {
            playFromBeginning()
            return true
        }
        return play(episode: episode, fileURL: fileURL, fromBeginning: true)
    }

    /// Play a feed-provided `podcast:soundbite`: seek to `startTime`, then **auto-pause** when
    /// wall-clock position reaches `startTime + duration`. Same episode / AVPlayer / progress —
    /// **not** a separate clip player. Pause at end is like user pause (no continuous queue advance).
    /// Requires finite duration > 0. Clears any prior end marker. If this episode is not current,
    /// starts playback (`fromBeginning: true`) then seeks into the window when media is available.
    @discardableResult
    func playSoundbite(
        episode: PodcastEpisode,
        startTimeSeconds: Double,
        durationSeconds: Double,
        fileURL: URL? = nil
    ) -> Bool {
        guard startTimeSeconds.isFinite, startTimeSeconds >= 0,
              durationSeconds.isFinite, durationSeconds > 0 else {
            return false
        }
        let end = startTimeSeconds + durationSeconds
        guard end.isFinite, end > startTimeSeconds else {
            return false
        }

        // A failed item cannot seek or play; load it fresh like a non-current episode.
        let isCurrent = currentEpisode?.id == episode.id && player != nil && !hasFailedItem
        if !isCurrent {
            // Fresh load at 0 so skip-intro / resume do not steal the soundbite start; seek next.
            guard play(episode: episode, fileURL: fileURL, fromBeginning: true) else {
                return false
            }
        }

        seek(toSeconds: startTimeSeconds, clearSoundbiteEndMarker: false)
        soundbiteEndSeconds = end

        if let player, !isPlaying {
            // Intentional soundbite start — do not apply rewind-after-pause.
            pausedAt = nil
            activateSession()
            player.play()
            player.rate = rate
            isPlaying = true
            resumeSleepTimerIfNeeded()
            updateNowPlayingInfo(force: true)
            applyIdleTimerPolicy()
        }
        return true
    }

    /// Cancel pending soundbite play-until-end (no-op when none armed).
    func clearSoundbiteEndMarker() {
        soundbiteEndSeconds = nil
    }

    /// Whether a soundbite end window is armed for the current item.
    var hasSoundbiteEndMarker: Bool {
        soundbiteEndSeconds != nil
    }

    // MARK: - Sleep timer

    /// Start a clock timer for the given minutes (replaces any active timer).
    func setSleepTimer(minutes: Int) {
        guard minutes > 0 else { return }
        clearSleepTimerState(restoreVolume: true)
        sleepTimerMode = .clock(minutes: minutes)
        isSleepTimerActive = true
        sleepTimerDidFade = false
        sleepVolume = 1.0
        player?.volume = 1.0
        let total = Double(minutes * 60)
        if isPlaying {
            sleepTimerEndDate = Date().addingTimeInterval(total)
            sleepTimerPausedRemaining = nil
            sleepTimerRemainingSeconds = total
        } else {
            sleepTimerEndDate = nil
            sleepTimerPausedRemaining = total
            sleepTimerRemainingSeconds = total
        }
    }

    /// Pause when the current episode ends (no clock countdown UI).
    func setSleepTimerEndOfEpisode() {
        clearSleepTimerState(restoreVolume: true)
        sleepTimerMode = .endOfEpisode
        isSleepTimerActive = true
        sleepTimerRemainingSeconds = nil
        sleepTimerEndDate = nil
        sleepTimerPausedRemaining = nil
        sleepTimerDidFade = false
        sleepVolume = 1.0
        player?.volume = 1.0
    }

    /// Pause when the current chapter ends (no clock countdown UI).
    /// Uses chapters already on `currentEpisode` (PSC / persisted Podcast Index / media).
    /// If chapters are not loaded yet, mode stays active and resolves the boundary once they appear
    /// (Full Player lazy-load updates `currentEpisode.chapters`). No invented chapter ends.
    func setSleepTimerEndOfChapter() {
        clearSleepTimerState(restoreVolume: true)
        sleepTimerMode = .endOfChapter
        isSleepTimerActive = true
        sleepTimerRemainingSeconds = nil
        sleepTimerEndDate = nil
        sleepTimerPausedRemaining = nil
        sleepTimerDidFade = false
        sleepVolume = 1.0
        player?.volume = 1.0
        refreshSleepTimerChapterEndTarget()
    }

    /// Stop after the Queue drains (no clock countdown UI).
    /// Clears clock dates / fade / chapter end marker like EOE; advances only via `nextQueueEpisode`
    /// while active — ignores Continuous Same podcast / Off for the advance decision. No volume fade.
    func setSleepTimerEndOfQueue() {
        clearSleepTimerState(restoreVolume: true)
        sleepTimerMode = .endOfQueue
        isSleepTimerActive = true
        sleepTimerRemainingSeconds = nil
        sleepTimerEndDate = nil
        sleepTimerPausedRemaining = nil
        sleepTimerDidFade = false
        sleepVolume = 1.0
        player?.volume = 1.0
    }

    /// Whether end-of-chapter is offered: current episode has ≥1 chapter with a start boundary.
    /// Prefers `currentEpisode.chapters`, else store copy (PSC / persisted Index / media).
    /// Full Player may still be lazy-loading — menus use loaded chapters only.
    var canSetSleepTimerEndOfChapter: Bool {
        !resolvedSleepTimerChapters.isEmpty
    }

    /// Chapters for sleep-timer end-of-chapter: player episode, else subscribed/queued store copy.
    private var resolvedSleepTimerChapters: [PodcastChapter] {
        guard let episode = currentEpisode else { return [] }
        if !episode.chapters.isEmpty { return episode.chapters }
        if let stored = store?.episode(id: episode.id), !stored.chapters.isEmpty {
            return stored.chapters
        }
        return []
    }

    func extendSleepTimer(byMinutes minutes: Int) {
        guard minutes > 0, isSleepTimerActive else { return }
        switch sleepTimerMode {
        case .clock:
            let current = sleepTimerRemainingSeconds ?? sleepTimerPausedRemaining ?? 0
            let next = current + Double(minutes * 60)
            cancelSleepTimerFade(restoreVolume: true)
            if isPlaying {
                sleepTimerEndDate = Date().addingTimeInterval(next)
                sleepTimerPausedRemaining = nil
            } else {
                sleepTimerEndDate = nil
                sleepTimerPausedRemaining = next
            }
            sleepTimerRemainingSeconds = next
        case .endOfEpisode, .endOfChapter, .endOfQueue, .none:
            setSleepTimer(minutes: minutes)
        }
    }

    func disableSleepTimer() {
        clearSleepTimerState(restoreVolume: true)
    }

    var sleepTimerStatusLabel: String? {
        guard isSleepTimerActive else { return nil }
        switch sleepTimerMode {
        case .endOfEpisode:
            return String(localized: "End of ep.")
        case .endOfChapter:
            return String(localized: "End of ch.")
        case .endOfQueue:
            return String(localized: "End of q.")
        case .clock:
            if let remaining = sleepTimerRemainingSeconds {
                return formatCountdown(remaining)
            }
            return String(localized: "Sleep")
        case .none:
            return nil
        }
    }

    /// VoiceOver label for mini / full player sleep controls (EN/DE catalog).
    /// Uses existing `sleepTimerRemainingSeconds` / mode — no separate timer.
    var sleepTimerAccessibilityLabel: String {
        guard isSleepTimerActive else {
            return String(localized: "Sleep timer")
        }
        switch sleepTimerMode {
        case .endOfEpisode:
            return String(localized: "Sleep timer, end of episode")
        case .endOfChapter:
            return String(localized: "Sleep timer, end of chapter")
        case .endOfQueue:
            return String(localized: "Sleep timer, end of queue")
        case .clock:
            guard let remaining = sleepTimerRemainingSeconds else {
                return String(localized: "Sleep timer")
            }
            if remaining < 60 {
                return String(localized: "Sleep timer, less than 1 minute remaining")
            }
            let minutes = Int((remaining / 60.0).rounded(.up))
            return String(localized: "Sleep timer, \(minutes) minutes remaining")
        case .none:
            return String(localized: "Sleep timer")
        }
    }

    // MARK: - Private


    /// `true` when auto-delete must wait: this episode is loaded and playing from a local file.
    func shouldBlockAutoDelete(for episodeId: String) -> Bool {
        currentEpisode?.id == episodeId && isPlayingFromLocalFile
    }

    /// Honor Settings playback-source preference via `DownloadService.localURL`.
    /// - Prefer download / Automatic: local file when present, else network URL.
    /// - Prefer stream: always network URL when available (falls back to local if no remote).
    /// Optional `preferredFileURL` is treated as a known local path (same as `localURL`) and
    /// still subject to Prefer stream.
    /// Optional `preferredMediaURL` (http(s) only): play that remote instead of the primary enclosure.
    /// Local download reuse requires the primary `downloadUrl` to match `preferredMediaURL`
    /// (downloads are keyed by episode id for the primary URL only).
    /// Stream URLs are additionally gated by `streamWifiOnly` in `play` (local files always OK).

    /// Feed override playback speed when set; otherwise AppSettings default.
    private func resolvedPlaybackSpeed(for episode: PodcastEpisode) -> Float {
        let global = settings?.defaultPlaybackSpeed ?? 1.0
        guard let store, let feed = store.feed(containingEpisodeId: episode.id) else {
            return global
        }
        return store.feedSettings(for: feed.id).resolvedPlaybackSpeed(global: global)
    }

    /// Feed duration when the RSS/Atom item has one; else a previously saved playback duration.
    /// `0` means unknown — skip intro may still seek (same as Android when duration is unknown).
    private func knownDurationSeconds(for episode: PodcastEpisode) -> Double {
        if episode.durationSeconds.isFinite, episode.durationSeconds > 0 {
            return episode.durationSeconds
        }
        let saved = store?.playbackState(for: episode.id).durationSeconds ?? 0
        if saved.isFinite, saved > 0 {
            return saved
        }
        return 0
    }

    /// False when a fresh-start intro seek would land at the end or inside the outro window.
    /// Unknown duration still allows the seek.
    private func skipIntroSeekFits(episode: PodcastEpisode, intro: Double) -> Bool {
        let duration = knownDurationSeconds(for: episode)
        guard duration > 0 else { return true }
        if intro >= duration { return false }
        let outro = Double(resolvedSkipOutroSeconds(for: episode))
        if outro > 0, outro < duration, duration - intro <= outro {
            return false
        }
        return true
    }

    /// Feed override skip-intro when set; otherwise AppSettings global.
    private func resolvedSkipIntroSeconds(for episode: PodcastEpisode) -> Int {
        let global = settings?.skipIntroSeconds ?? 0
        guard let store, let feed = store.feed(containingEpisodeId: episode.id) else {
            return global
        }
        return store.feedSettings(for: feed.id).resolvedSkipIntroSeconds(global: global)
    }

    /// Feed override skip-outro when set; otherwise AppSettings global.
    private func resolvedSkipOutroSeconds(for episode: PodcastEpisode) -> Int {
        let global = settings?.skipOutroSeconds ?? 0
        guard let store, let feed = store.feed(containingEpisodeId: episode.id) else {
            return global
        }
        return store.feedSettings(for: feed.id).resolvedSkipOutroSeconds(global: global)
    }

    private func resolvePlaybackURL(
        for episode: PodcastEpisode,
        preferredFileURL: URL?,
        preferredMediaURL: URL? = nil
    ) -> URL? {
        let preference = settings?.playbackSourcePreference ?? .automatic
        let local = preferredFileURL ?? downloads?.localURL(for: episode)
        // Local folder episodes need security-scoped access before AVPlayer can open the file.
        if let local, local.isFileURL, let store {
            LocalFolderAccess.ensureAccessForEpisodeFileURL(local, feeds: store.feeds)
        }

        // Alternate / override http(s) media (e.g. podcast:alternateEnclosure source).
        // Same episode identity; stream the chosen URL unless a primary download matches it.
        if let preferred = preferredMediaURL {
            let scheme = preferred.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            let primaryRemote = episode.downloadUrl.flatMap { EpisodeMediaURL.url(from: $0) }
            let urlsMatch = primaryRemote.map {
                $0.absoluteString == preferred.absoluteString
            } ?? false
            switch preference {
            case .preferStream:
                return preferred
            case .preferDownload, .automatic:
                if urlsMatch, let local { return local }
                return preferred
            }
        }

        let remote = episode.downloadUrl.flatMap { EpisodeMediaURL.url(from: $0) }

        switch preference {
        case .preferStream:
            if let remote { return remote }
            return local
        case .preferDownload, .automatic:
            if let local { return local }
            return remote
        }
    }

    /// Resume when there is progress and the episode is not already marked played.
    private func resumePosition(for episodeId: String) -> Double {
        guard let store else {
            return 0
        }
        let state = store.playbackState(for: episodeId)
        if state.isPlayed {
            return 0
        }
        return max(0, state.positionSeconds)
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self else { return }
                // Drop samples from a torn-down player and from the playhead that
                // still sits before an in-flight seek (resume / scrub / intro).
                guard self.player === player else { return }
                guard !self.isSeekHoldActive else { return }
                guard seconds.isFinite else { return }
                self.positionSeconds = max(0, seconds)
                if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                    self.durationSeconds = duration
                }
                self.persistProgress(force: false)
                self.tickSleepTimer()
                self.checkEndOfChapterSleepTimer()
                self.checkSoundbiteEnd()
                self.checkSkipOutro()
                self.updateNowPlayingInfo(force: false)
            }
        }
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // A queued callback from the player play() just replaced must not
                // pause the new item's clock sleep timer (that countdown never restarts).
                guard self.player === player else { return }
                // Live status: receive(on:) can deliver an earlier .paused after
                // playback has already started, which would freeze the clock timer.
                let playing = player.timeControlStatus == .playing
                if self.isPlaying && !playing {
                    self.pauseSleepTimerCountdown()
                } else if !self.isPlaying && playing {
                    // resumeSleepTimerIfNeeded returns immediately unless isPlaying is already true.
                    self.isPlaying = true
                    self.resumeSleepTimerIfNeeded()
                }
                // play() is documented to set rate to 1.0. Re-apply the session/feed
                // speed once the item is actually playing, or a 1.5× label still plays at 1×.
                if playing, abs(player.rate - self.rate) > 0.01 {
                    player.rate = self.rate
                }
                self.isPlaying = playing
                self.updateNowPlayingInfo(force: true)
                self.applyIdleTimerPolicy()
            }

        // play() does not clear the previous episode's length, and play() publishes
        // Now Playing before this item's duration is known. Drop that length so the
        // existing publish writes no duration. The 0.5s tick is throttled and stops
        // while paused, so the first finite duration of this item is written once.
        durationSeconds = 0
        didWriteLoadedItemDuration = false
        durationCancellable = item.publisher(for: \.duration)
            .receive(on: RunLoop.main)
            .sink { [weak self] duration in
                guard let self else { return }
                guard self.player === player else { return }
                let seconds = duration.seconds
                guard seconds.isFinite, seconds > 0 else { return }
                guard !self.didWriteLoadedItemDuration else { return }
                self.didWriteLoadedItemDuration = true
                self.durationSeconds = seconds
                self.updateNowPlayingInfo(force: true)
                self.store?.publishWidgetSnapshot()
            }

        itemStatusCancellable = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self, self.player === player, status == .failed else { return }
                self.handleItemFailure(message: item.error?.localizedDescription)
            }
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor in
                guard let self, self.player === player else { return }
                self.handleItemFailure(message: message)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    /// Stream could not load or lost the network mid-episode. Without this the player sat on a
    /// dead item: no audio, no alert, and Play did nothing. Saves the position, shows paused,
    /// and reports the system error once (status change and notification can both arrive).
    private func handleItemFailure(message: String?) {
        persistProgress(force: true)
        if isPlaying {
            isPlaying = false
            pauseSleepTimerCountdown()
            updateNowPlayingInfo(force: true)
            applyIdleTimerPolicy()
        }
        if lastError == nil {
            lastError = message
                ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown).localizedDescription
        }
    }

    private func handlePlaybackEnded() {
        // Natural episode end — drop any pending soundbite window (queue advance is separate).
        clearSoundbiteEndMarker()
        // End-of-episode: mark finished, stop — do not auto-advance.
        // End-of-chapter: pause + notify, including when the chapter end is the episode
        // end. The 0.5s observer only pauses inside 50ms of the boundary, so the last
        // chapter usually arrives here via didPlayToEndTime. Do not mark played or
        // dismiss the player — same result as a mid-chapter expiry.
        // End-of-queue: advance via `nextQueueEpisode` only (keep EOQ active while queue continues);
        // when no next / play fails → same teardown as EOE (no Same-podcast / Off fallback).
        if isSleepTimerActive, let mode = sleepTimerMode {
            switch mode {
            case .endOfChapter:
                if let seconds = player?.currentTime().seconds, seconds.isFinite {
                    positionSeconds = max(0, seconds)
                }
                expireSleepTimer()
                return
            case .endOfEpisode:
                let finishedId = currentEpisode?.id
                finishCurrentEpisode(ended: true)
                expireSleepTimer()
                tearDownPlayer(clearSleepTimer: false)
                deactivateSessionAfterPlaybackStopped()
                currentEpisode = nil
                isPlayingFromLocalFile = false
                positionSeconds = 0
                durationSeconds = 0
                clearNowPlayingInfo()
                if let finishedId {
                    store?.flushAutoDeleteAfterPlaying(for: finishedId)
                }
                store?.publishWidgetSnapshot()
                applyIdleTimerPolicy()
                return
            case .endOfQueue:
                let finishedId = currentEpisode?.id
                // Snapshot next before markPlayed removes the finished item from the queue.
                let next = finishedId.flatMap { store?.nextQueueEpisode(after: $0) }
                finishCurrentEpisode(ended: true)
                // play(next) persists the live playhead for the episode it leaves.
                // That would put the skip/end position back after markPlayed cleared it.
                if let finishedId {
                    adoptSavedPlaybackPosition(episodeId: finishedId)
                }
                var startedNext = false
                if let next {
                    // play() keeps an active sleep timer across episode changes (clearSleepTimer: false).
                    startedNext = play(episode: next)
                }
                if startedNext {
                    // Keep EOQ active — do not expire while Queue still advances.
                    applyIdleTimerPolicy()
                    return
                }
                expireSleepTimer()
                tearDownPlayer(clearSleepTimer: false)
                deactivateSessionAfterPlaybackStopped()
                currentEpisode = nil
                isPlayingFromLocalFile = false
                positionSeconds = 0
                durationSeconds = 0
                clearNowPlayingInfo()
                if let finishedId {
                    store?.flushAutoDeleteAfterPlaying(for: finishedId)
                }
                store?.publishWidgetSnapshot()
                applyIdleTimerPolicy()
                return
            case .clock:
                break
            }
        }

        let finishedId = currentEpisode?.id
        // Snapshot next before markPlayed removes the finished item from the queue (Queue mode)
        // and before the finished id is marked played (Same podcast still finds it by id).
        // Mode: Off → no advance; Queue → `nextQueueEpisode` only; Same podcast →
        // `nextSamePodcastEpisode` only (never auto-jumps Queue when Same podcast is selected).
        let mode = settings?.continuousPlaybackMode ?? .queue
        let next: PodcastEpisode?
        switch mode {
        case .off:
            next = nil
        case .queue:
            next = finishedId.flatMap { store?.nextQueueEpisode(after: $0) }
        case .samePodcast:
            next = finishedId.flatMap { store?.nextSamePodcastEpisode(after: $0) }
        }
        finishCurrentEpisode(ended: true)
        // Same handoff as end-of-queue: do not let play(next) restore the pre-reset playhead.
        if let finishedId {
            adoptSavedPlaybackPosition(episodeId: finishedId)
        }
        var startedNext = false
        if let next {
            // play() switches away and flushes deferred auto-delete for the finished episode.
            // May refuse when stream Wi‑Fi-only blocks cellular streaming.
            startedNext = play(episode: next)
        }
        if !startedNext {
            isPlaying = false
            pauseSleepTimerCountdown()
            tearDownPlayer(clearSleepTimer: false)
            deactivateSessionAfterPlaybackStopped()
            currentEpisode = nil
            isPlayingFromLocalFile = false
            positionSeconds = 0
            durationSeconds = 0
            clearNowPlayingInfo()
            if let finishedId {
                store?.flushAutoDeleteAfterPlaying(for: finishedId)
            }
            store?.publishWidgetSnapshot()
            applyIdleTimerPolicy()
        } else {
            // Continuous next started — play() already called applyIdleTimerPolicy.
            applyIdleTimerPolicy()
        }
    }

    /// `markPlayed` may zero `positionSeconds` (Reset position when marked played).
    /// `play(next)` then calls `finishCurrentEpisode(ended: false)`, which persists the
    /// in-memory playhead and would undo that reset whenever smart-mark does not
    /// cover the stop point (smart mark off, or skip outro longer than the window).
    /// Copy the saved position so the follow-up persist keeps 0, or the kept position
    /// when reset is off.
    private func adoptSavedPlaybackPosition(episodeId: String) {
        guard let store else { return }
        let saved = store.playbackState(for: episodeId).positionSeconds
        guard saved.isFinite else { return }
        positionSeconds = max(0, saved)
    }

    /// Save progress; mark played when ended or within configurable smart-mark window.
    private func finishCurrentEpisode(ended: Bool) {
        guard let episode = currentEpisode, let store else {
            return
        }
        persistProgress(force: true)
        if ended {
            store.markPlayed(episode.id, removeFromQueue: true)
        } else if smartMarkSuppressedEpisodeId != episode.id,
                  almostEnded(position: positionSeconds, duration: durationSeconds) {
            store.markPlayed(episode.id, removeFromQueue: true)
        }
    }

    /// Explicit Mark unplayed on the loaded episode: skip smart mark when leaving it
    /// in this play session. No-op for other episodes.
    func suppressSmartMarkAfterMarkUnplayed(for episodeId: String) {
        guard currentEpisode?.id == episodeId else { return }
        smartMarkSuppressedEpisodeId = episodeId
    }

    /// When remaining ≤ skipOutroSeconds (duration known and longer than the outro),
    /// finish once like natural end. Outro ≥ duration must not auto-finish: remaining
    /// would always be ≤ outro, so a short episode would be marked played after ~1s.
    private func checkSkipOutro() {
        guard !didTriggerSkipOutroForSession else { return }
        guard let episode = currentEpisode else { return }
        let outro = Double(resolvedSkipOutroSeconds(for: episode))
        guard outro > 0 else { return }
        guard durationSeconds.isFinite, durationSeconds > 0 else { return }
        // Android SkipUtils: skip ending only when skipEnd < duration.
        guard outro < durationSeconds else { return }
        // Avoid firing at t≈0 before any real progress.
        guard positionSeconds > 1 else { return }
        let remaining = durationSeconds - positionSeconds
        guard remaining.isFinite, remaining <= outro else { return }
        didTriggerSkipOutroForSession = true
        handlePlaybackEnded()
    }

    /// Feed soundbite play-until-end: pause at wall-clock `soundbiteEndSeconds` like user pause.
    /// Does **not** call `handlePlaybackEnded` — no continuous advance / mark-played-from-end.
    private func checkSoundbiteEnd() {
        guard let end = soundbiteEndSeconds, end.isFinite else { return }
        guard isPlaying else { return }
        // Small epsilon so 0.5s observer cadence does not need an exact hit.
        if positionSeconds + 0.05 >= end {
            pauseForSoundbiteEnd(at: end)
        }
    }

    private func pauseForSoundbiteEnd(at end: Double) {
        clearSoundbiteEndMarker()
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        // Snap to the feed end boundary for an honest stop position.
        let target: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            target = min(max(0, end), durationSeconds)
        } else {
            target = max(0, end)
        }
        let time = CMTime(seconds: target, preferredTimescale: 600)
        let hold = beginSeekHold()
        let seekingPlayer = player
        seekingPlayer.seek(to: time) { [weak self] _ in
            Task { @MainActor in
                self?.endSeekHold(hold)
            }
        }
        positionSeconds = target
        persistProgress(force: true)
        pauseSleepTimerCountdown()
        cancelSleepTimerFade(restoreVolume: true)
        recordPausedAt()
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
    }

    private func almostEnded(position: Double, duration: Double) -> Bool {
        guard duration.isFinite, duration > 0 else {
            return false
        }
        let threshold = Double(
            settings?.smartMarkAsPlayedSeconds ?? Int(Self.defaultSmartMarkAsPlayedSeconds)
        )
        // Off (0): only natural end (`ended: true`) or explicit mark — not near-end leave/stop/scrub.
        guard threshold > 0 else {
            return false
        }
        return position >= duration - threshold
    }

    /// Ignore periodic samples until `token` (the latest seek) completes.
    private var isSeekHoldActive: Bool { activeSeekHold != nil }

    private func beginSeekHold() -> Int {
        seekHoldToken += 1
        activeSeekHold = seekHoldToken
        return seekHoldToken
    }

    /// Release the hold only if no newer seek has started.
    private func endSeekHold(_ token: Int) {
        guard activeSeekHold == token else { return }
        activeSeekHold = nil
    }

    /// Scene left the foreground. The periodic observer only writes every
    /// `persistIntervalSeconds`, so a kill in that window would resume early.
    func persistProgressBeforeBackground() {
        persistProgress(force: true)
    }

    private func persistProgress(force: Bool) {
        guard let episode = currentEpisode, let store else {
            return
        }
        // NaN/infinite would make JSONEncoder throw and skip the whole playback.json write.
        guard positionSeconds.isFinite else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastPersistedAt) < Self.persistIntervalSeconds {
            return
        }
        lastPersistedAt = now
        // Keep a mark-played reset (0) while this episode stays loaded.
        // The live playhead is unchanged; only the saved position is held.
        let positionToSave: Double
        if markPlayedResetHoldEpisodeId == episode.id {
            let stored = store.playbackState(for: episode.id).positionSeconds
            positionToSave = stored.isFinite ? max(0, stored) : 0
        } else {
            positionToSave = positionSeconds
        }
        store.saveProgress(
            episodeId: episode.id,
            positionSeconds: positionToSave,
            durationSeconds: durationSeconds
        )
    }

    /// Remember that `markPlayed` just zeroed this loaded episode.
    /// No-op when it is not the current item (nothing will persist over it).
    func holdMarkPlayedPositionReset(for episodeId: String) {
        guard currentEpisode?.id == episodeId else { return }
        markPlayedResetHoldEpisodeId = episodeId
    }

    /// Drop the reset hold after mark played with reset off.
    func releaseMarkPlayedPositionReset(for episodeId: String) {
        guard markPlayedResetHoldEpisodeId == episodeId else { return }
        markPlayedResetHoldEpisodeId = nil
    }

    private func tickSleepTimer() {
        guard isSleepTimerActive, case .clock = sleepTimerMode else { return }
        guard isPlaying, let endDate = sleepTimerEndDate else { return }

        let remaining = endDate.timeIntervalSinceNow
        sleepTimerRemainingSeconds = max(0, remaining)

        if remaining <= 0 {
            expireSleepTimer()
            return
        }

        let fadeOn = settings?.sleepTimerFadeEnabled ?? true
        if fadeOn, remaining < Self.fadeThresholdSeconds {
            applyFade(remaining: remaining)
        } else if sleepTimerDidFade {
            // Extended past fade window, or fade disabled mid-window → restore.
            cancelSleepTimerFade(restoreVolume: true)
        }
    }

    private func applyFade(remaining: Double) {
        // Linear fade toward 0 over the last `fadeThresholdSeconds` (Android Media3
        // millisLeft / NOTIFICATION_THRESHOLD). Soft `AVPlayer.volume` only — volume
        // boost stays on AVAudioMix; volume adaptation is session mode, not a multiplier.
        let fraction = max(0.0, min(1.0, remaining / Self.fadeThresholdSeconds))
        let volume = Float(fraction)
        sleepVolume = volume
        player?.volume = volume
        sleepTimerDidFade = true
    }

    /// Cancel an in-progress clock sleep fade and optionally restore `AVPlayer.volume`
    /// to the pre-fade level (`1.0` on the player path; boost remains on the mix).
    /// Used on user pause / seek / disable / fire restore / Settings off.
    func cancelSleepTimerFade(restoreVolume: Bool) {
        guard sleepTimerDidFade || sleepVolume < 0.999 else {
            if restoreVolume {
                sleepVolume = 1.0
                player?.volume = 1.0
            }
            sleepTimerDidFade = false
            return
        }
        sleepTimerDidFade = false
        if restoreVolume {
            sleepVolume = 1.0
            player?.volume = 1.0
        }
    }

    /// End-of-chapter: resolve boundary when chapters/duration become known; expire at chapter end.
    /// No clock fade — same pause + notify path as end-of-episode mid-play (via `expireSleepTimer`).
    private func checkEndOfChapterSleepTimer() {
        guard isSleepTimerActive, case .endOfChapter = sleepTimerMode else { return }
        guard isPlaying else { return }
        refreshSleepTimerChapterEndTarget()
        guard let end = sleepTimerChapterEndSeconds, end.isFinite else { return }
        // Small epsilon so 0.5s observer cadence does not need an exact hit.
        if positionSeconds + 0.05 >= end {
            expireSleepTimer()
        }
    }

    /// Snap chapter-end target once: chapter at activation position (or first chapter if before first).
    /// Retries while `nil` when chapters load later or last-chapter duration becomes known.
    private func refreshSleepTimerChapterEndTarget() {
        guard isSleepTimerActive, case .endOfChapter = sleepTimerMode else { return }
        guard sleepTimerChapterEndSeconds == nil else { return }
        let chapters = resolvedSleepTimerChapters
        guard !chapters.isEmpty else { return }
        // Keep player episode in sync when store already has chapters (Mini enable path).
        if var current = currentEpisode, current.chapters.isEmpty {
            current.chapters = chapters
            currentEpisode = current
        }
        let duration: Double? =
            (durationSeconds.isFinite && durationSeconds > 0) ? durationSeconds : nil
        let index = ChapterIndexing.currentIndex(in: chapters, at: positionSeconds) ?? 0
        sleepTimerChapterEndSeconds = ChapterIndexing.endSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: duration
        )
    }

    private func expireSleepTimer() {
        // Sleep-timer fire cancels pending soundbite end (user-equivalent stop).
        clearSoundbiteEndMarker()
        let notificationKind: SleepTimerEndNotificationCoordinator.Kind
        switch sleepTimerMode {
        case .endOfEpisode:
            notificationKind = .endOfEpisode
        case .endOfChapter:
            notificationKind = .endOfChapter
        case .endOfQueue:
            notificationKind = .endOfQueue
        case .clock, .none:
            notificationKind = .clock
        }
        if let player, isPlaying {
            player.pause()
            isPlaying = false
        }
        recordPausedAt()
        // AntennaPod rewinds slightly after fade so the listener does not lose content.
        // Clock fade only — EOE / EOC / EOQ do not fade.
        if sleepTimerDidFade {
            let rewind = Self.fadeThresholdSeconds / 2
            let target = max(0, positionSeconds - rewind)
            let time = CMTime(seconds: target, preferredTimescale: 600)
            if let seekingPlayer = player {
                let hold = beginSeekHold()
                seekingPlayer.seek(to: time) { [weak self] _ in
                    Task { @MainActor in
                        self?.endSeekHold(hold)
                    }
                }
            }
            positionSeconds = target
        }
        persistProgress(force: true)
        clearSleepTimerState(restoreVolume: true)
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
        // Local banner (+ foreground haptic) once per fire; Settings toggle default on.
        Task {
            await SleepTimerEndNotificationCoordinator.notifyIfNeeded(
                kind: notificationKind,
                settings: settings
            )
        }
    }

    private func pauseSleepTimerCountdown() {
        guard isSleepTimerActive, case .clock = sleepTimerMode else { return }
        if let endDate = sleepTimerEndDate {
            sleepTimerPausedRemaining = max(0, endDate.timeIntervalSinceNow)
            sleepTimerRemainingSeconds = sleepTimerPausedRemaining
            sleepTimerEndDate = nil
        }
    }

    private func resumeSleepTimerIfNeeded() {
        guard isSleepTimerActive, case .clock = sleepTimerMode else { return }
        guard isPlaying else { return }
        if let paused = sleepTimerPausedRemaining {
            sleepTimerEndDate = Date().addingTimeInterval(paused)
            sleepTimerRemainingSeconds = paused
            sleepTimerPausedRemaining = nil
        } else if sleepTimerEndDate == nil, let remaining = sleepTimerRemainingSeconds {
            sleepTimerEndDate = Date().addingTimeInterval(remaining)
        }
    }

    private func clearSleepTimerState(restoreVolume: Bool) {
        sleepTimerMode = nil
        isSleepTimerActive = false
        sleepTimerRemainingSeconds = nil
        sleepTimerEndDate = nil
        sleepTimerPausedRemaining = nil
        sleepTimerChapterEndSeconds = nil
        // Cancel fade + restore (disable / fire / replace timer).
        cancelSleepTimerFade(restoreVolume: restoreVolume)
    }

    private func tearDownPlayer(clearSleepTimer: Bool) {
        clearSoundbiteEndMarker()
        if clearSleepTimer {
            disableSleepTimer()
        } else {
            pauseSleepTimerCountdown()
        }
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        activeSeekHold = nil
        statusCancellable = nil
        durationCancellable = nil
        videoTrackPolicyCancellable?.cancel()
        videoTrackPolicyCancellable = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        itemStatusCancellable = nil
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
        }
        failedToEndObserver = nil
        pictureInPicture.tearDown()
        player?.pause()
        player = nil
    }

    /// Re-apply `AVAudioSession` category/mode + preferred output channels after Settings changes
    /// (volume adaptation / video→audio-only / stereo→mono) while a player item is loaded.
    /// No-op when nothing is playing or loaded.
    func applyAudioSessionConfiguration() {
        guard player != nil else { return }
        activateSession()
    }

    /// Re-apply `AVPlayerItem.audioTimePitchAlgorithm` after Settings **Preserve pitch** changes
    /// while a player item is loaded. No-op when nothing is loaded.
    func applyTimePitchAlgorithm() {
        guard let item = player?.currentItem else { return }
        applyTimePitchAlgorithm(to: item)
    }

    /// Re-apply / cancel sleep-timer fade after Settings **Sleep timer volume fade** changes.
    /// When turned off mid-fade, restores pre-fade `AVPlayer.volume` immediately.
    func applySleepTimerFadePreference() {
        let fadeOn = settings?.sleepTimerFadeEnabled ?? true
        if !fadeOn {
            cancelSleepTimerFade(restoreVolume: true)
        }
        // When turned on, next `tickSleepTimer` applies fade if still in the last 10s.
    }

    /// Re-apply soft **Volume boost** (`AVMutableAudioMix` track volume) after Settings changes
    /// while a player item is loaded. No-op when nothing is loaded.
    func applyVolumeBoost() {
        guard let item = player?.currentItem else { return }
        applyVolumeBoost(to: item)
    }

    /// Re-apply video-track enable/disable after Settings **Play video as audio only** changes
    /// while a player item is loaded. Live toggle — no full restart required. No-op when nothing loaded.
    func applyVideoAsAudioOnlyPolicy() {
        guard let item = player?.currentItem else { return }
        applyVideoAsAudioOnlyPolicy(to: item)
    }

    /// Map Settings **Preserve pitch** to stock `AVPlayerItem.audioTimePitchAlgorithm`.
    /// On (default) → `.timeDomain` (speech-oriented pitch correction when rate ≠ 1×).
    /// Off → `.varispeed` (pitch scales with rate — chipmunk / slow voice). Keeps stock AVPlayer.
    private func applyTimePitchAlgorithm(to item: AVPlayerItem) {
        // Default on when settings unbound (matches AppSettings default / speech-friendly iOS default).
        let preserve = settings?.preservePitchEnabled ?? true
        item.audioTimePitchAlgorithm = preserve ? .timeDomain : .varispeed
    }

    /// Soft volume boost via `AVMutableAudioMix` track volume (Settings **Volume boost** percent / 100).
    ///
    /// - **100%** → clear mix (unity / no soft gain).
    /// - **>100%** (up to 300%) → `setVolume(factor, at: .zero)` on each audio track. Apple documents
    ///   mix volume in 0…1; values above 1.0 are used here as **software gain** and **may clip / distort**.
    /// - Sleep-timer fade remains on `AVPlayer.volume` (0…1) and multiplies with the mix.
    /// - Keeps stock `AVPlayer` (video / PiP / Now Playing). **Not** ReplayGain / loudness normalization /
    ///   Android `LoudnessEnhancer`. **Not** `AVAudioEngine` (would break those surfaces).
    /// - Some streams (notably HLS) may ignore `audioMix` — boost then has no effect for that item.
    private func applyVolumeBoost(to item: AVPlayerItem) {
        let percent = AppSettings.clampVolumeBoostPercent(settings?.volumeBoostPercent ?? 100)
        let factor = Float(percent) / 100.0
        if factor <= 1.001 {
            item.audioMix = nil
            player?.volume = sleepVolume
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.player?.currentItem === item else { return }
            let livePercent = AppSettings.clampVolumeBoostPercent(self.settings?.volumeBoostPercent ?? 100)
            let liveFactor = Float(livePercent) / 100.0
            if liveFactor <= 1.001 {
                item.audioMix = nil
                self.player?.volume = self.sleepVolume
                return
            }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard self.player?.currentItem === item else { return }
                guard !tracks.isEmpty else {
                    // No audio tracks yet / unsupported for mix — leave unity (no fake boost).
                    item.audioMix = nil
                    self.player?.volume = self.sleepVolume
                    return
                }
                var params: [AVAudioMixInputParameters] = []
                for track in tracks {
                    let p = AVMutableAudioMixInputParameters(track: track)
                    p.setVolume(liveFactor, at: .zero)
                    params.append(p)
                }
                let mix = AVMutableAudioMix()
                mix.inputParameters = params
                item.audioMix = mix
                // Sleep fade stays on player.volume; boost is on the mix.
                self.player?.volume = self.sleepVolume
            } catch {
                item.audioMix = nil
                self.player?.volume = self.sleepVolume
            }
        }
    }

    /// Configure stock `AVPlayer` for video→audio-only without remuxing.
    ///
    /// When Settings **Play video as audio only** is on, disables `AVPlayerItem` video tracks
    /// (`AVPlayerItemTrack.isEnabled = false`) so playback continues as audio without requiring a
    /// video layer / PiP surface. When off, re-enables video tracks.
    ///
    /// **Honesty:**
    /// - Does **not** strip or remux video bits out of the file — same media URL / item.
    /// - Background audio (UIBackgroundModes audio) continues; no PiP obligation in audio-only mode.
    /// - Streaming / HLS / adaptive containers may still download a video stream or variant; disabling
    ///   tracks does not force an audio-only rendition selection.
    /// - Tracks often arrive after the item becomes ready — observe `AVPlayerItem.tracks` and re-apply.
    /// - Live toggle: no player restart; Full player hides the surface separately via Settings binding.
    private func applyVideoAsAudioOnlyPolicy(to item: AVPlayerItem) {
        videoTrackPolicyCancellable?.cancel()
        videoTrackPolicyCancellable = nil

        let apply: () -> Void = { [weak self] in
            guard let self, self.player?.currentItem === item else { return }
            let audioOnly = self.settings?.playVideoAsAudioOnly == true
            for track in item.tracks {
                guard track.assetTrack?.mediaType == .video else { continue }
                let shouldEnable = !audioOnly
                if track.isEnabled != shouldEnable {
                    track.isEnabled = shouldEnable
                }
            }
        }

        apply()
        videoTrackPolicyCancellable = item.publisher(for: \.tracks)
            .receive(on: RunLoop.main)
            .sink { _ in apply() }
    }

    /// Keep screen awake only while Settings **Keep screen on** is enabled and playback is actively playing.
    /// Uses `UIApplication.shared.isIdleTimerDisabled`. Restores `false` when paused/stopped/no episode/toggle off.
    /// Honesty: idle timer only — does not override Low Power Mode beyond that; no brightness hacks; PiP/background audio unchanged.
    func applyIdleTimerPolicy() {
        let activelyPlaying = isPlaying || (player?.rate ?? 0) > 0
        let shouldDisableIdle =
            (settings?.keepScreenOnWhilePlaying == true)
            && activelyPlaying
            && currentEpisode != nil
        if UIApplication.shared.isIdleTimerDisabled != shouldDisableIdle {
            UIApplication.shared.isIdleTimerDisabled = shouldDisableIdle
        }
    }

    /// Choose session mode from Settings + current media:
    /// - Volume adaptation on → `.spokenAudio` (speech-oriented; **not** Android loudness gain)
    /// - Off + video surface path → `.moviePlayback`
    /// - Off + audio / audio-only video → `.default`
    private func preferredAudioSessionMode() -> AVAudioSession.Mode {
        if settings?.volumeAdaptationEnabled == true {
            return .spokenAudio
        }
        if let episode = currentEpisode, episode.isVideo, settings?.playVideoAsAudioOnly != true {
            return .moviePlayback
        }
        return .default
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        let mode = preferredAudioSessionMode()
        do {
            try session.setCategory(.playback, mode: mode, options: [])
            applyPreferredOutputChannelCount(on: session)
            try session.setActive(true)
        } catch {
            // `.spokenAudio` should work with `.playback`; if the mode is rejected, fall back to `.voiceChat`
            // when volume adaptation is on, else `.default`.
            let fallback: AVAudioSession.Mode =
                settings?.volumeAdaptationEnabled == true ? .voiceChat : .default
            do {
                try session.setCategory(.playback, mode: fallback, options: [])
                applyPreferredOutputChannelCount(on: session)
                try session.setActive(true)
            } catch {
            }
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        setupAudioSessionObserversIfNeeded()
    }

    /// Player is torn down (Stop, last episode finished, end-of-episode / end-of-queue sleep
    /// timer). Release the session so audio this app interrupted (Music, another podcast app)
    /// gets `.shouldResume`; the next play re-activates via `activateSession()`. Best-effort.
    private func deactivateSessionAfterPlaybackStopped() {
        guard player == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Best-effort mono / stereo preference via `AVAudioSession.setPreferredOutputNumberOfChannels`.
    /// When Stereo to mono is on → request 1 channel; when off → request up to 2 (or max available).
    ///
    /// **Why not `AVMutableAudioMix` / channel volume?** Mix input parameters only scale track volume —
    /// they do **not** remix L+R → mono. A real channel downmix on `AVPlayerItem` needs
    /// `MTAudioProcessingTap` (file-based only; **not** HLS/`audioMix`-unsupported streams) or a custom
    /// `AVAudioEngine` graph (would break shared video surface / PiP / Now Playing). This beta keeps
    /// stock `AVPlayer` and uses the session preferred-channel API instead (route-dependent; system may ignore).
    private func applyPreferredOutputChannelCount(on session: AVAudioSession) {
        let maxChannels = session.maximumOutputNumberOfChannels
        guard maxChannels >= 1 else { return }
        let preferred: Int
        if settings?.stereoToMonoEnabled == true {
            preferred = 1
        } else {
            preferred = min(2, maxChannels)
        }
        do {
            try session.setPreferredOutputNumberOfChannels(preferred)
        } catch {
            // Route may reject preferred channel count — best-effort only; do not fail playback.
        }
    }


    // MARK: - Audio session interruptions / route changes

    /// Headset unplug + phone-call style interruptions. Bluetooth play/pause buttons
    /// stay on MPRemoteCommandCenter — we only pause/resume AVPlayer and refresh Now Playing.
    private func setupAudioSessionObserversIfNeeded() {
        guard !audioSessionObserversConfigured else { return }
        audioSessionObserversConfigured = true
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }

        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            // Capture play intent before system-driven pause races the status publisher.
            let wasPlaying = isPlaying || (player?.rate ?? 0) > 0
            resumeAfterInterruption = wasPlaying
            if wasPlaying {
                pauseForAudioSessionEvent()
            }
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume)
            if shouldResume, resumeAfterInterruption, currentEpisode != nil, player != nil, !isPlaying {
                resumeAfterInterruption = false
                resumeAfterAudioSessionEvent()
            } else {
                resumeAfterInterruption = false
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }
        // Headphones / wireless audio device became unavailable — standard pause.
        // Do not treat newDeviceAvailable / category changes as pause.
        if reason == .oldDeviceUnavailable {
            resumeAfterInterruption = false
            if isPlaying || (player?.rate ?? 0) > 0 {
                pauseForAudioSessionEvent()
            }
            return
        }
        // Re-apply Stereo to mono (preferred output channels) when the route changes
        // (new device, category, override) so the preference sticks across speaker ↔ BT ↔ CarPlay.
        // Best-effort only — system may still ignore preferred channel count on the new route.
        if player != nil {
            applyPreferredOutputChannelCount(on: AVAudioSession.sharedInstance())
        }
    }

    /// Pause via the same bookkeeping as user pause (progress, sleep timer, Now Playing).
    private func pauseForAudioSessionEvent() {
        guard player != nil else { return }
        player?.pause()
        if isPlaying {
            isPlaying = false
            persistProgress(force: true)
            pauseSleepTimerCountdown()
            cancelSleepTimerFade(restoreVolume: true)
            recordPausedAt()
        }
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
    }

    private func resumeAfterAudioSessionEvent() {
        guard let player, currentEpisode != nil else { return }
        // Interruption end / route change must not claim playing on a dead item; the failure
        // alert is already up and the next Play rebuilds the stream.
        guard !hasFailedItem else { return }
        applyRewindAfterPauseIfNeeded()
        activateSession()
        player.play()
        player.rate = rate
        isPlaying = true
        resumeSleepTimerIfNeeded()
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
    }

    /// Remember pause time for rewind-after-pause (only if not already paused).
    private func recordPausedAt() {
        if pausedAt == nil {
            pausedAt = Date()
        }
    }

    /// When Settings rewind-after-pause > 0 and pause lasted ≥ 1s, seek back by N seconds.
    /// Clears `pausedAt`. No-op on cold play (`pausedAt == nil`).
    private func applyRewindAfterPauseIfNeeded() {
        defer { pausedAt = nil }
        let rewindSecs = settings?.rewindAfterPauseSeconds ?? AppSettings.defaultRewindAfterPauseSeconds
        guard rewindSecs > 0, let pausedAt else { return }
        let pausedFor = Date().timeIntervalSince(pausedAt)
        guard pausedFor >= AppSettings.rewindAfterPauseMinimumPauseSeconds else { return }
        let target = max(0, positionSeconds - Double(rewindSecs))
        if abs(target - positionSeconds) < 0.05 {
            return
        }
        // Automatic rewind is not a listener seek; keep a mark-played reset.
        seek(toSeconds: target, releasesMarkPlayedResetHold: false, resnapsSleepTimerChapterEnd: false)
    }

    // MARK: - Now Playing / remote commands

    /// Lockscreen, Control Center, Bluetooth, and system Now Playing (incl. CarPlay audio surface).
    /// No custom CPTemplate / CarPlay scene — that needs Apple CarPlay audio entitlement.
    private func setupRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPlaying {
                    self.togglePlayPause()
                }
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying {
                    self.togglePlayPause()
                }
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(bySeconds: self.fastForwardSeconds)
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(bySeconds: -self.rewindSeconds)
            }
            return .success
        }

        applyRemoteSkipIntervals()

        // Steering-wheel next/previous often fire these instead of skip+/-; map to Settings intervals.
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(bySeconds: self.fastForwardSeconds)
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(bySeconds: -self.rewindSeconds)
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let targetPosition = positionEvent.positionTime
            Task { @MainActor in
                self?.seek(toSeconds: targetPosition)
            }
            return .success
        }
    }

    /// Refresh Lockscreen / Control Center skip button intervals from `AppSettings`.
    func applyRemoteSkipIntervals() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: fastForwardSeconds)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: rewindSeconds)]
    }

    private func updateNowPlayingInfo(force: Bool) {
        guard currentEpisode != nil else {
            clearNowPlayingInfo()
            return
        }
        let now = Date()
        if !force, now.timeIntervalSince(lastNowPlayingUpdateAt) < Self.nowPlayingUpdateIntervalSeconds {
            return
        }
        lastNowPlayingUpdateAt = now
        applyRemoteSkipIntervals()

        guard let episode = currentEpisode else { return }
        let feed = store?.feed(containingEpisodeId: episode.id)
        let feedName = feed.map { store?.displayTitle(for: $0) ?? $0.title } ?? "Podcast"

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = episode.title
        info[MPMediaItemPropertyArtist] = feedName
        info[MPMediaItemPropertyAlbumTitle] = feedName
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        if durationSeconds.isFinite, durationSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, positionSeconds)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)
        if let artwork = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        cachedArtwork = nil
        cachedArtworkURL = nil
        lastNowPlayingUpdateAt = .distantPast
    }

    private func loadArtworkIfNeeded() {
        guard let episode = currentEpisode else { return }
        let feed = store?.feed(containingEpisodeId: episode.id)
        let resolved = store?.episode(id: episode.id) ?? episode
        let imageUrl = resolved.preferredPodcastImagesArtworkURL
            ?? feed?.preferredDisplayArtworkURL
        guard let imageUrl, !imageUrl.isEmpty, imageUrl != cachedArtworkURL else {
            if imageUrl == nil || imageUrl?.isEmpty == true {
                cachedArtwork = nil
                cachedArtworkURL = nil
                // Paused playback has no tick to drop a cover that refresh removed.
                updateNowPlayingInfo(force: true)
            }
            return
        }
        // URL(string:) rejects a cover address that contains a space. EpisodeMediaURL
        // percent-encodes that. An address it still cannot read must not keep the
        // previous cover, and must not download.
        guard let url = EpisodeMediaURL.url(from: imageUrl) else {
            cachedArtwork = nil
            cachedArtworkURL = nil
            updateNowPlayingInfo(force: true)
            return
        }
        // play() already wrote Now Playing with the previous episode's cover.
        // Drop it before the download, including while paused. An unchanged URL
        // returned above and did not reach here.
        cachedArtwork = nil
        cachedArtworkURL = nil
        updateNowPlayingInfo(force: true)
        let episodeId = episode.id
        Task {
            do {
                let (data, _) = try await AppURLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    guard self.currentEpisode?.id == episodeId else { return }
                    self.cachedArtworkURL = imageUrl
                    self.cachedArtwork = artwork
                    self.updateNowPlayingInfo(force: true)
                }
            } catch {
                // Artwork is best-effort; playback continues without it.
            }
        }
    }

    private func formatCountdown(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
