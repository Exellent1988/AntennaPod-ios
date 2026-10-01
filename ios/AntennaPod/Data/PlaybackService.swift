import AVFoundation
import Combine
import Foundation

/// Clock / end-of-episode sleep timer modes for beta (AntennaPod P0 basis).
enum SleepTimerMode: Equatable {
    case clock(minutes: Int)
    case endOfEpisode
}

@MainActor
final class PlaybackService: ObservableObject {
    /// AntennaPod default (`prefSmartMarkAsPlayedSecs` = 30).
    static let smartMarkAsPlayedSeconds: Double = 30
    /// Throttle JSON writes while the periodic observer fires every 0.5s.
    private static let persistIntervalSeconds: Double = 5
    /// Soft fade window matching Android `SleepTimer.NOTIFICATION_THRESHOLD` (10s).
    static let fadeThresholdSeconds: Double = 10

    static let clockPresetsMinutes: [Int] = [5, 10, 15, 30, 45, 60]

    @Published var currentEpisode: PodcastEpisode?
    @Published var isPlaying = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0

    /// Remaining seconds when a clock timer is active; `nil` when inactive or end-of-episode mode.
    @Published private(set) var sleepTimerRemainingSeconds: Double?
    @Published private(set) var sleepTimerMode: SleepTimerMode?
    @Published private(set) var isSleepTimerActive = false

    /// Bound from the app for progress / played / continuous queue.
    weak var store: PodcastStore?
    /// Bound so continuous playback prefers offline files when present.
    weak var downloads: DownloadService?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var lastPersistedAt: Date = .distantPast

    private var sleepTimerEndDate: Date?
    private var sleepTimerPausedRemaining: Double?
    private var sleepTimerDidFade = false
    private var sleepVolume: Float = 1.0

    func play(episode: PodcastEpisode, fileURL: URL? = nil) {
        if let current = currentEpisode, current.id != episode.id {
            finishCurrentEpisode(ended: false)
        }

        let resolvedFile = fileURL ?? downloads?.localURL(for: episode)
        let source: URL?
        if let resolvedFile {
            source = resolvedFile
        } else if let remote = episode.downloadUrl {
            source = URL(string: remote)
        } else {
            source = nil
        }
        guard let url = source else {
            return
        }

        // Keep an active sleep timer across episode changes (clock continues; EOE re-arms).
        tearDownPlayer(clearSleepTimer: false)
        currentEpisode = episode
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.rate = rate
        newPlayer.volume = sleepVolume
        player = newPlayer
        observe(player: newPlayer, item: item)

        let resumeAt = resumePosition(for: episode.id)
        if resumeAt > 1 {
            let time = CMTime(seconds: resumeAt, preferredTimescale: 600)
            newPlayer.seek(to: time) { [weak self] finished in
                Task { @MainActor in
                    guard let self, finished else { return }
                    self.positionSeconds = resumeAt
                }
            }
            positionSeconds = resumeAt
        } else {
            positionSeconds = 0
        }

        newPlayer.play()
        isPlaying = true
        activateSession()
        resumeSleepTimerIfNeeded()
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
        } else {
            player.play()
            player.rate = rate
            isPlaying = true
            resumeSleepTimerIfNeeded()
        }
    }

    func stop() {
        finishCurrentEpisode(ended: false)
        tearDownPlayer(clearSleepTimer: true)
        currentEpisode = nil
        isPlaying = false
        positionSeconds = 0
        durationSeconds = 0
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying {
            player?.rate = newRate
        }
    }

    func seek(bySeconds delta: Double) {
        guard let player else {
            return
        }
        let target = max(0, positionSeconds + delta)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time)
        positionSeconds = target
        persistProgress(force: true)
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
            finishCurrentEpisode(ended: true)
            expireSleepTimer()
            tearDownPlayer(clearSleepTimer: false)
            currentEpisode = nil
            positionSeconds = 0
            durationSeconds = 0
            return
        }

        let finishedId = currentEpisode?.id
        // Snapshot next before markPlayed removes the finished item from the queue.
        let next = finishedId.flatMap { store?.nextQueueEpisode(after: $0) }
        finishCurrentEpisode(ended: true)
        if let next {
            play(episode: next, fileURL: downloads?.localURL(for: next))
        } else {
            isPlaying = false
            pauseSleepTimerCountdown()
            tearDownPlayer(clearSleepTimer: false)
            currentEpisode = nil
            positionSeconds = 0
            durationSeconds = 0
        }
    }

    /// Save progress; mark played when ended or within smart-mark window (last 30s).
    private func finishCurrentEpisode(ended: Bool) {
        guard let episode = currentEpisode, let store else {
            return
        }
        persistProgress(force: true)
        if ended || almostEnded(position: positionSeconds, duration: durationSeconds) {
            store.markPlayed(episode.id, removeFromQueue: true)
        }
    }

    private func almostEnded(position: Double, duration: Double) -> Bool {
        guard duration.isFinite, duration > 0 else {
            return false
        }
        return position >= duration - Self.smartMarkAsPlayedSeconds
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
        player?.pause()
        player = nil
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
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
