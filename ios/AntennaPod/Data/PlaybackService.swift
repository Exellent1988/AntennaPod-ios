import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackService: ObservableObject {
    @Published var currentEpisode: PodcastEpisode?
    @Published var isPlaying = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?

    func play(episode: PodcastEpisode, fileURL: URL? = nil) {
        let source: URL?
        if let fileURL {
            source = fileURL
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
        observe(player: newPlayer)
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
        } else {
            player.play()
            player.rate = rate
            isPlaying = true
        }
    }

    func stop() {
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
    }

    private func observe(player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.positionSeconds = time.seconds
                if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                    self?.durationSeconds = duration
                }
            }
        }
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
            }
    }

    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusCancellable = nil
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
