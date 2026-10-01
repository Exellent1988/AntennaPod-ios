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
    /// AntennaPod default (`prefSmartMarkAsPlayedSecs` = 30).
    static let smartMarkAsPlayedSeconds: Double = 30
    /// Throttle JSON writes while the periodic observer fires every 0.5s.
    private static let persistIntervalSeconds: Double = 5
    /// Soft fade window matching Android `SleepTimer.NOTIFICATION_THRESHOLD` (10s).
    static let fadeThresholdSeconds: Double = 10

    static let clockPresetsMinutes: [Int] = [5, 10, 15, 30, 45, 60]
    /// Match mini player skip buttons.
    static let skipDeltaSeconds: Double = 30
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

    /// Bound from the app for progress / played / continuous queue.
    weak var store: PodcastStore?
    /// Bound so continuous playback prefers offline files when present.
    weak var downloads: DownloadService?
    /// Bound for default playback speed on new episode starts.
    weak var settings: AppSettings?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
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

    func play(episode: PodcastEpisode, fileURL: URL? = nil) {
        let isFreshEpisode = currentEpisode?.id != episode.id
        if let current = currentEpisode, current.id != episode.id {
            finishCurrentEpisode(ended: false)
        }

        // Fresh episode (or first play): use Settings default speed.
        if isFreshEpisode {
            rate = settings?.defaultPlaybackSpeed ?? 1.0
        }

        guard let url = resolvePlaybackURL(for: episode, preferredFileURL: fileURL) else {
            return
        }
        let playingLocal = url.isFileURL

        // Keep an active sleep timer across episode changes (clock continues; EOE re-arms).
        tearDownPlayer(clearSleepTimer: false)
        currentEpisode = episode
        isPlayingFromLocalFile = playingLocal
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
                    self.updateNowPlayingInfo(force: true)
                }
            }
            positionSeconds = resumeAt
        } else {
            positionSeconds = 0
        }

        newPlayer.play()
        isPlaying = true
        activateSession()
        setupRemoteCommandsIfNeeded()
        resumeSleepTimerIfNeeded()
        updateNowPlayingInfo(force: true)
        loadArtworkIfNeeded()
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
        updateNowPlayingInfo(force: true)
    }

    func stop() {
        resumeAfterInterruption = false
        finishCurrentEpisode(ended: false)
        tearDownPlayer(clearSleepTimer: true)
        currentEpisode = nil
        isPlayingFromLocalFile = false
        isPlaying = false
        positionSeconds = 0
        durationSeconds = 0
        clearNowPlayingInfo()
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying {
            player?.rate = newRate
        }
        updateNowPlayingInfo(force: true)
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


    /// Honor Settings playback-source preference via `DownloadService.localURL`.
    /// - Prefer download / Automatic: local file when present, else network URL.
    /// - Prefer stream: always network URL when available (falls back to local if no remote).
    /// Optional `preferredFileURL` is treated as a known local path (same as `localURL`) and
    /// still subject to Prefer stream.
    private func resolvePlaybackURL(for episode: PodcastEpisode, preferredFileURL: URL?) -> URL? {
        let preference = settings?.playbackSourcePreference ?? .automatic
        let local = preferredFileURL ?? downloads?.localURL(for: episode)
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
            isPlayingFromLocalFile = false
            positionSeconds = 0
            durationSeconds = 0
            clearNowPlayingInfo()
            return
        }

        let finishedId = currentEpisode?.id
        // Snapshot next before markPlayed removes the finished item from the queue.
        let next = finishedId.flatMap { store?.nextQueueEpisode(after: $0) }
        finishCurrentEpisode(ended: true)
        if let next {
            play(episode: next)
        } else {
            isPlaying = false
            pauseSleepTimerCountdown()
            tearDownPlayer(clearSleepTimer: false)
            currentEpisode = nil
            isPlayingFromLocalFile = false
            positionSeconds = 0
            durationSeconds = 0
            clearNowPlayingInfo()
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
        updateNowPlayingInfo(force: true)
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
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        setupAudioSessionObserversIfNeeded()
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
        }
        updateNowPlayingInfo(force: true)
    }

    private func resumeAfterAudioSessionEvent() {
        guard let player, currentEpisode != nil else { return }
        activateSession()
        player.play()
        player.rate = rate
        isPlaying = true
        resumeSleepTimerIfNeeded()
        updateNowPlayingInfo(force: true)
    }

    // MARK: - Now Playing / remote commands

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
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipDeltaSeconds)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.seek(bySeconds: Self.skipDeltaSeconds)
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipDeltaSeconds)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.seek(bySeconds: -Self.skipDeltaSeconds)
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

        guard let episode = currentEpisode else { return }
        let feed = store?.feed(containingEpisodeId: episode.id)

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = episode.title
        info[MPMediaItemPropertyArtist] = feed?.title ?? "Podcast"
        info[MPMediaItemPropertyAlbumTitle] = feed?.title ?? "Podcast"
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
