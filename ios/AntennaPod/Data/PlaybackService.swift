import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackService: ObservableObject {
    /// AntennaPod default (`prefSmartMarkAsPlayedSecs` = 30).
    static let smartMarkAsPlayedSeconds: Double = 30
    /// Throttle JSON writes while the periodic observer fires every 0.5s.
    private static let persistIntervalSeconds: Double = 5

    @Published var currentEpisode: PodcastEpisode?
    @Published var isPlaying = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0

    /// Bound from the app for progress / played / continuous queue.
    weak var store: PodcastStore?
    /// Bound so continuous playback prefers offline files when present.
    weak var downloads: DownloadService?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var lastPersistedAt: Date = .distantPast

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

        tearDownPlayer()
        currentEpisode = episode
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.rate = rate
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
        } else {
            player.play()
            player.rate = rate
            isPlaying = true
        }
    }

    func stop() {
        finishCurrentEpisode(ended: false)
        tearDownPlayer()
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
            }
        }
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
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
        let finishedId = currentEpisode?.id
        // Snapshot next before markPlayed removes the finished item from the queue.
        let next = finishedId.flatMap { store?.nextQueueEpisode(after: $0) }
        finishCurrentEpisode(ended: true)
        if let next {
            play(episode: next, fileURL: downloads?.localURL(for: next))
        } else {
            isPlaying = false
            tearDownPlayer()
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

    private func tearDownPlayer() {
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
}
