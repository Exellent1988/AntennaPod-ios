import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Thin `AVPlayerLayer` host for the full player (no system VideoPlayer chrome).
/// Shares `PlaybackService`'s `AVPlayer` so transport / scrub stay in sync.
/// Optionally wires `AVPictureInPictureController` (iOS 15+ playerLayer path) for beta lite PiP.
struct EpisodeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    /// When non-nil, attach / refresh PiP against this surface's player layer.
    var pictureInPicture: PictureInPictureSession?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.isAccessibilityElement = true
        view.accessibilityLabel = String(localized: "Video")
        context.coordinator.bind(session: pictureInPicture, host: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.isPlayerDetachedForBackground {
            // Progress ticks re-render while backgrounded; re-attaching here would let iOS
            // pause the player again. Remember the (possibly new) player for the return.
            uiView.replaceBackgroundDetachedPlayer(with: player)
        } else if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        context.coordinator.bind(session: pictureInPicture, host: uiView)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.dismantle(host: uiView)
    }

    final class Coordinator {
        func bind(session: PictureInPictureSession?, host: PlayerContainerView) {
            session?.attach(to: host)
        }

        func dismantle(host: PlayerContainerView) {
            // Session may retain the host while PiP is active (see PictureInPictureSession).
            host.pictureInPictureSession?.handleSurfaceDismantled(host: host)
        }
    }

    final class PlayerContainerView: UIView {
        weak var pictureInPictureSession: PictureInPictureSession?
        /// Player taken off the layer while the app is in the background (see below).
        private weak var backgroundDetachedPlayer: AVPlayer?

        var isPlayerDetachedForBackground: Bool {
            backgroundDetachedPlayer != nil
        }

        func replaceBackgroundDetachedPlayer(with player: AVPlayer) {
            backgroundDetachedPlayer = player
        }
        private var lifecycleObservers: [NSObjectProtocol] = []

        override class var layerClass: AnyClass { AVPlayerLayer.self }

        override init(frame: CGRect) {
            super.init(frame: frame)
            // iOS pauses an AVPlayer that still drives a visible-app AVPlayerLayer when the
            // app goes to the background (lock screen with the full player open), so a video
            // podcast went silent. Unless Picture in Picture is starting or showing this
            // layer, detach the player for the background and re-attach it on return.
            let center = NotificationCenter.default
            lifecycleObservers.append(center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.detachPlayerForBackgroundIfNeeded() }
            })
            lifecycleObservers.append(center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reattachPlayerAfterBackground() }
            })
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        }

        private func detachPlayerForBackgroundIfNeeded() {
            guard let player = playerLayer.player else { return }
            if pictureInPictureSession?.isEngaged(with: playerLayer) == true {
                return
            }
            backgroundDetachedPlayer = player
            playerLayer.player = nil
        }

        private func reattachPlayerAfterBackground() {
            guard let player = backgroundDetachedPlayer else { return }
            backgroundDetachedPlayer = nil
            if playerLayer.player == nil {
                playerLayer.player = player
            }
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}

/// Owns `AVPictureInPictureController` for the full-player video surface (beta lite).
/// Retains the layer host while PiP is active so dismissing the sheet does not immediately end PiP.
@MainActor
final class PictureInPictureSession: ObservableObject {
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false

    private var controller: AVPictureInPictureController?
    /// Set from will-start until did-stop / failed. Read synchronously on background entry:
    /// automatic PiP from inline begins before `isActive` (published async) flips.
    private var isStartingOrActive = false
    private let delegateProxy = DelegateProxy()
    private var possibleObservation: NSKeyValueObservation?
    private var activeObservation: NSKeyValueObservation?
    /// Keeps `AVPlayerLayer` alive after the SwiftUI surface is dismantled while PiP runs.
    private var retainedHost: EpisodeVideoSurface.PlayerContainerView?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func attach(to host: EpisodeVideoSurface.PlayerContainerView) {
        host.pictureInPictureSession = self

        // Already bound to this layer — keep controller; clear retain if SwiftUI re-embedded us.
        if let controller, controller.playerLayer === host.playerLayer {
            if retainedHost === host {
                retainedHost = nil
            }
            return
        }

        // PiP already running on another host/layer — do not steal AVPlayer onto a second layer.
        if controller?.isPictureInPictureActive == true {
            return
        }

        // Switching idle hosts: replace controller.
        tearDownObservationsAndController(stopIfActive: false)

        guard isSupported else {
            isPossible = false
            isActive = false
            return
        }

        guard let pip = AVPictureInPictureController(playerLayer: host.playerLayer) else {
            isPossible = false
            isActive = false
            return
        }

        // Nice-to-have: home / app switch while the inline surface is visible.
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        delegateProxy.onStartingOrActiveChange = { [weak self] engaged in
            // AVKit calls the delegate on the main thread; stay synchronous for background entry.
            MainActor.assumeIsolated { self?.isStartingOrActive = engaged }
        }
        pip.delegate = delegateProxy
        controller = pip

        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                self?.isPossible = ctrl.isPictureInPicturePossible
            }
        }
        activeObservation = pip.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isActive = ctrl.isPictureInPictureActive
                if !ctrl.isPictureInPictureActive {
                    self.releaseRetainedHostIfNeeded()
                }
            }
        }
    }

    /// PiP is starting or showing `layer`, so the player must stay on it in the background.
    func isEngaged(with layer: AVPlayerLayer) -> Bool {
        guard let controller, controller.playerLayer === layer else { return false }
        return isStartingOrActive || controller.isPictureInPictureActive
    }

    func start() {
        guard let controller, controller.isPictureInPicturePossible else { return }
        controller.startPictureInPicture()
    }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    /// Full player surface went away — keep the host alive only while PiP is showing.
    func handleSurfaceDismantled(host: EpisodeVideoSurface.PlayerContainerView) {
        if controller?.isPictureInPictureActive == true, controller?.playerLayer === host.playerLayer {
            retainedHost = host
            // Detach from any residual superview; layer stays owned by retainedHost.
            host.removeFromSuperview()
        } else if retainedHost !== host {
            // Surface replaced / audio-only — clear if this host is idle.
            if controller?.playerLayer === host.playerLayer {
                tearDown()
            }
        }
    }

    /// Call when leaving video mode (audio-only), episode change, or player teardown.
    func tearDown() {
        tearDownObservationsAndController(stopIfActive: true)
        releaseRetainedHostIfNeeded()
        isPossible = false
        isActive = false
    }

    private func tearDownObservationsAndController(stopIfActive: Bool) {
        possibleObservation?.invalidate()
        activeObservation?.invalidate()
        possibleObservation = nil
        activeObservation = nil
        if stopIfActive, controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
        controller?.delegate = nil
        controller = nil
        isStartingOrActive = false
    }

    private func releaseRetainedHostIfNeeded() {
        retainedHost?.pictureInPictureSession = nil
        retainedHost = nil
    }
}

/// `AVPictureInPictureControllerDelegate` needs an `NSObject`; forwards start/stop only.
private final class DelegateProxy: NSObject, AVPictureInPictureControllerDelegate {
    var onStartingOrActiveChange: ((Bool) -> Void)?

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onStartingOrActiveChange?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        onStartingOrActiveChange?(false)
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        onStartingOrActiveChange?(false)
    }
}
