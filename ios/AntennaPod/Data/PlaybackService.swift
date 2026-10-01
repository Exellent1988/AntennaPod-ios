import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

/// Clock / end-of-episode sleep timer modes for beta (AntennaPod P0 basis).
enum SleepTimerMode: Equatable {
    case clock(minutes: Int)
    case endOfEpisode
}

@MainActor
final class PlaybackService: ObservableObject {
    /// Fallback when settings unbound (AntennaPod `prefSmartMarkAsPlayedSecs` default = 30).
    static let defaultSmartMarkAsPlayedSeconds: Double = 30
    /// Throttle JSON writes while the periodic observer fires every 0.5s.
    private static let persistIntervalSeconds: Double = 5
    /// Soft fade window matching Android `SleepTimer.NOTIFICATION_THRESHOLD` (10s).
    static let fadeThresholdSeconds: Double = 10

    static let clockPresetsMinutes: [Int] = [5, 10, 15, 30, 45, 60]
    /// Custom sleep timer UI range (minutes). Presets stay 5–60; fade unchanged.
    static let customSleepTimerMinutesRange: ClosedRange<Int> = 1...180
    /// Throttle lock-screen elapsed updates (system interpolates via rate + timestamp).
    private static let nowPlayingUpdateIntervalSeconds: Double = 5

    @Published var currentEpisode: PodcastEpisode?
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

    static let streamCellularBlockedMessage =
        "Streaming is Wi‑Fi only. Connect to Wi‑Fi or Ethernet, play a downloaded episode, or turn off Stream Wi‑Fi only in Settings → Network / Downloads."

    /// Bound from the app for progress / played / continuous queue.
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
    private var pipCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var lastPersistedAt: Date = .distantPast

    private var sleepTimerEndDate: Date?
    private var sleepTimerPausedRemaining: Double?
    private var sleepTimerDidFade = false
    private var sleepVolume: Float = 1.0

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

    init() {
        setupRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        pipCancellable = pictureInPicture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Starts or switches playback. Returns `false` when streaming is blocked by Wi‑Fi-only policy
    /// (current player left unchanged; `lastError` set for UI).
    /// - Parameter fromBeginning: When `true`, start at position 0 (ignore saved resume) and do **not**
    ///   apply skip-intro — user asked for the literal start. Does not flip played/unplayed flags.
    @discardableResult
    func play(episode: PodcastEpisode, fileURL: URL? = nil, fromBeginning: Bool = false) -> Bool {
        guard let url = resolvePlaybackURL(for: episode, preferredFileURL: fileURL) else {
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

        let isFreshEpisode = currentEpisode?.id != episode.id
        var leavingEpisodeId: String?
        if let current = currentEpisode, current.id != episode.id {
            leavingEpisodeId = current.id
            finishCurrentEpisode(ended: false)
        }

        // Fresh episode (or first play): feed override speed, else Settings default.
        if isFreshEpisode {
            rate = resolvedPlaybackSpeed(for: episode)
        }

        // Keep an active sleep timer across episode changes (clock continues; EOE re-arms).
        tearDownPlayer(clearSleepTimer: false)
        currentEpisode = episode
        isPlayingFromLocalFile = playingLocal
        // Local file no longer the active player item — run deferred auto-delete if pending.
        if let leavingEpisodeId {
            store?.flushAutoDeleteAfterPlaying(for: leavingEpisodeId)
        }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.rate = rate
        newPlayer.volume = sleepVolume
        player = newPlayer
        observe(player: newPlayer, item: item)

        // New play session for this episode item — reset intro/outro once-guards.
        didApplySkipIntroForSession = false
        didTriggerSkipOutroForSession = false
        // Cold play / episode (re)start is not a pause-resume — do not rewind-after-pause.
        pausedAt = nil

        let resumeAt = fromBeginning ? 0 : resumePosition(for: episode.id)
        if resumeAt > 1 {
            let time = CMTime(seconds: resumeAt, preferredTimescale: 600)
            newPlayer.seek(to: time) { [weak self] finished in
                Task { @MainActor in
                    guard let self, finished else { return }
                    self.positionSeconds = resumeAt
                    self.updateNowPlayingInfo(force: true)
                }
            }
            positionSeconds = resumeAt
        } else if fromBeginning {
            // Explicit play-from-beginning: absolute 0, no skip-intro.
            positionSeconds = 0
        } else {
            // Fresh start (position ≈ 0): skip intro once when configured (feed override else global).
            let intro = Double(resolvedSkipIntroSeconds(for: episode))
            if intro > 0 {
                let time = CMTime(seconds: intro, preferredTimescale: 600)
                newPlayer.seek(to: time) { [weak self] finished in
                    Task { @MainActor in
                        guard let self, finished else { return }
                        self.positionSeconds = intro
                        self.didApplySkipIntroForSession = true
                        self.updateNowPlayingInfo(force: true)
                    }
                }
                positionSeconds = intro
                didApplySkipIntroForSession = true
            } else {
                positionSeconds = 0
            }
        }

        newPlayer.play()
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
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
            // Pause only saves progress; smart-mark happens on leave/end (AntennaPod-like).
            persistProgress(force: true)
            pauseSleepTimerCountdown()
            recordPausedAt()
        } else {
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

    func stop() {
        resumeAfterInterruption = false
        pausedAt = nil
        let leavingId = currentEpisode?.id
        finishCurrentEpisode(ended: false)
        tearDownPlayer(clearSleepTimer: true)
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

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying {
            player?.rate = newRate
        }
        updateNowPlayingInfo(force: true)
    }

    /// AntennaPod-style: advance session rate to the next `AppSettings.speedPresets` value (wraps).
    /// If the current rate is not a preset, jumps to the first preset (same as Android `setNextPlaybackSpeed`).
    func cycleToNextSpeedPreset() {
        let presets = AppSettings.speedPresets
        guard !presets.isEmpty else { return }
        if let idx = presets.firstIndex(of: rate), idx + 1 < presets.count {
            setRate(presets[idx + 1])
        } else {
            setRate(presets[0])
        }
    }

    func seek(bySeconds delta: Double) {
        seek(toSeconds: positionSeconds + delta)
    }

    /// Absolute seek for scrubber / Now Playing position changes.
    func seek(toSeconds seconds: Double) {
        guard let player else {
            return
        }
        let target = max(0, seconds)
        let capped: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            capped = min(target, durationSeconds)
        } else {
            capped = target
        }
        let time = CMTime(seconds: capped, preferredTimescale: 600)
        player.seek(to: time)
        positionSeconds = capped
        persistProgress(force: true)
        updateNowPlayingInfo(force: true)
    }

    /// Restart the **currently loaded** episode at position 0 and continue/start playback.
    /// If already playing → seek to 0 and keep playing. If paused → seek to 0 and play.
    /// Progress is persisted via `seek` / `saveProgress` only — does **not** flip played/unplayed.
    func playFromBeginning() {
        guard currentEpisode != nil, player != nil else { return }
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

    func extendSleepTimer(byMinutes minutes: Int) {
        guard minutes > 0, isSleepTimerActive else { return }
        switch sleepTimerMode {
        case .clock:
            let current = sleepTimerRemainingSeconds ?? sleepTimerPausedRemaining ?? 0
            let next = current + Double(minutes * 60)
            sleepTimerDidFade = false
            sleepVolume = 1.0
            player?.volume = 1.0
            if isPlaying {
                sleepTimerEndDate = Date().addingTimeInterval(next)
                sleepTimerPausedRemaining = nil
            } else {
                sleepTimerEndDate = nil
                sleepTimerPausedRemaining = next
            }
            sleepTimerRemainingSeconds = next
        case .endOfEpisode, .none:
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
            return "End of ep."
        case .clock:
            if let remaining = sleepTimerRemainingSeconds {
                return formatCountdown(remaining)
            }
            return "Sleep"
        case .none:
            return nil
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
    /// Stream URLs are additionally gated by `streamWifiOnly` in `play` (local files always OK).

    /// Feed override playback speed when set; otherwise AppSettings default.
    private func resolvedPlaybackSpeed(for episode: PodcastEpisode) -> Float {
        let global = settings?.defaultPlaybackSpeed ?? 1.0
        guard let store, let feed = store.feed(containingEpisodeId: episode.id) else {
            return global
        }
        return store.feedSettings(for: feed.id).resolvedPlaybackSpeed(global: global)
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

    private func resolvePlaybackURL(for episode: PodcastEpisode, preferredFileURL: URL?) -> URL? {
        let preference = settings?.playbackSourcePreference ?? .automatic
        let local = preferredFileURL ?? downloads?.localURL(for: episode)
        // Local folder episodes need security-scoped access before AVPlayer can open the file.
        if let local, local.isFileURL, let store {
            LocalFolderAccess.ensureAccessForEpisodeFileURL(local, feeds: store.feeds)
        }
        let remote = episode.downloadUrl.flatMap { URL(string: $0) }

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
            Task { @MainActor in
                guard let self else { return }
                self.positionSeconds = time.seconds
                if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                    self.durationSeconds = duration
                }
                self.persistProgress(force: false)
                self.tickSleepTimer()
                self.checkSkipOutro()
                self.updateNowPlayingInfo(force: false)
            }
        }
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                let playing = status == .playing
                if self.isPlaying && !playing {
                    self.pauseSleepTimerCountdown()
                } else if !self.isPlaying && playing {
                    self.resumeSleepTimerIfNeeded()
                }
                self.isPlaying = playing
                self.updateNowPlayingInfo(force: true)
                self.applyIdleTimerPolicy()
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

    private func handlePlaybackEnded() {
        // End-of-episode sleep timer: mark finished, stop — do not auto-advance queue.
        if case .endOfEpisode = sleepTimerMode, isSleepTimerActive {
            let finishedId = currentEpisode?.id
            finishCurrentEpisode(ended: true)
            expireSleepTimer()
            tearDownPlayer(clearSleepTimer: false)
            currentEpisode = nil
            isPlayingFromLocalFile = false
            positionSeconds = 0
            durationSeconds = 0
            clearNowPlayingInfo()
            if let finishedId {
                store?.flushAutoDeleteAfterPlaying(for: finishedId)
            }
            applyIdleTimerPolicy()
            return
        }

        let finishedId = currentEpisode?.id
        // Snapshot next before markPlayed removes the finished item from the queue.
        // When continuous playback is off, finish without auto-advancing (same stop path as no-next).
        let continuous = settings?.continuousPlaybackEnabled ?? true
        let next = continuous ? finishedId.flatMap { store?.nextQueueEpisode(after: $0) } : nil
        finishCurrentEpisode(ended: true)
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
            currentEpisode = nil
            isPlayingFromLocalFile = false
            positionSeconds = 0
            durationSeconds = 0
            clearNowPlayingInfo()
            if let finishedId {
                store?.flushAutoDeleteAfterPlaying(for: finishedId)
            }
            applyIdleTimerPolicy()
        } else {
            // Continuous next started — play() already called applyIdleTimerPolicy.
            applyIdleTimerPolicy()
        }
    }

    /// Save progress; mark played when ended or within configurable smart-mark window.
    private func finishCurrentEpisode(ended: Bool) {
        guard let episode = currentEpisode, let store else {
            return
        }
        persistProgress(force: true)
        if ended || almostEnded(position: positionSeconds, duration: durationSeconds) {
            store.markPlayed(episode.id, removeFromQueue: true)
        }
    }

    /// When remaining ≤ skipOutroSeconds (duration known), finish once like natural end.
    private func checkSkipOutro() {
        guard !didTriggerSkipOutroForSession else { return }
        guard let episode = currentEpisode else { return }
        let outro = Double(resolvedSkipOutroSeconds(for: episode))
        guard outro > 0 else { return }
        guard durationSeconds.isFinite, durationSeconds > 0 else { return }
        // Avoid firing at t≈0 before any real progress (short media + large outro).
        guard positionSeconds > 1 else { return }
        let remaining = durationSeconds - positionSeconds
        guard remaining.isFinite, remaining <= outro else { return }
        didTriggerSkipOutroForSession = true
        handlePlaybackEnded()
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

    private func persistProgress(force: Bool) {
        guard let episode = currentEpisode, let store else {
            return
        }
        let now = Date()
        if !force, now.timeIntervalSince(lastPersistedAt) < Self.persistIntervalSeconds {
            return
        }
        lastPersistedAt = now
        store.saveProgress(
            episodeId: episode.id,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
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

        if remaining < Self.fadeThresholdSeconds {
            applyFade(remaining: remaining)
        } else if sleepTimerDidFade {
            sleepTimerDidFade = false
            sleepVolume = 1.0
            player?.volume = 1.0
        }
    }

    private func applyFade(remaining: Double) {
        // Same step curve idea as Android multiplicators over the last 10s.
        let multiplicators: [Float] = [0.1, 0.2, 0.3, 0.3, 0.3, 0.4, 0.4, 0.4, 0.6, 0.8]
        let index = max(0, min(multiplicators.count - 1, Int(remaining)))
        let volume = multiplicators[index]
        sleepVolume = volume
        player?.volume = volume
        sleepTimerDidFade = true
    }

    private func expireSleepTimer() {
        if let player, isPlaying {
            player.pause()
            isPlaying = false
        }
        recordPausedAt()
        // AntennaPod rewinds slightly after fade so the listener does not lose content.
        if sleepTimerDidFade {
            let rewind = Self.fadeThresholdSeconds / 2
            let target = max(0, positionSeconds - rewind)
            let time = CMTime(seconds: target, preferredTimescale: 600)
            player?.seek(to: time)
            positionSeconds = target
        }
        persistProgress(force: true)
        clearSleepTimerState(restoreVolume: true)
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
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
        sleepTimerDidFade = false
        if restoreVolume {
            sleepVolume = 1.0
            player?.volume = 1.0
        }
    }

    private func tearDownPlayer(clearSleepTimer: Bool) {
        if clearSleepTimer {
            disableSleepTimer()
        } else {
            pauseSleepTimerCountdown()
        }
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusCancellable = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
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

    /// Best-effort mono / stereo preference via `setPreferredOutputNumberOfChannels`.
    /// When Stereo to mono is on → request 1 channel; when off → request up to 2 (or max available).
    /// The system may ignore this depending on the route (speaker, BT, CarPlay, etc.). Keeps stock AVPlayer.
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
        guard reason == .oldDeviceUnavailable else { return }
        resumeAfterInterruption = false
        if isPlaying || (player?.rate ?? 0) > 0 {
            pauseForAudioSessionEvent()
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
            recordPausedAt()
        }
        updateNowPlayingInfo(force: true)
        applyIdleTimerPolicy()
    }

    private func resumeAfterAudioSessionEvent() {
        guard let player, currentEpisode != nil else { return }
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
        seek(toSeconds: target)
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

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = episode.title
        info[MPMediaItemPropertyArtist] = feed?.title ?? "Podcast"
        info[MPMediaItemPropertyAlbumTitle] = feed?.title ?? "Podcast"
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
        let imageUrl = store?.feed(containingEpisodeId: episode.id)?.imageUrl
        guard let imageUrl, !imageUrl.isEmpty, imageUrl != cachedArtworkURL else {
            if imageUrl == nil || imageUrl?.isEmpty == true {
                cachedArtwork = nil
                cachedArtworkURL = nil
            }
            return
        }
        guard let url = URL(string: imageUrl) else { return }
        let episodeId = episode.id
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
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
