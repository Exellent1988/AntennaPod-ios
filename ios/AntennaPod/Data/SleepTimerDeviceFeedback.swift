import AudioToolbox
import CoreMotion
import Foundation
import PodcastCore

/// Device side of the sleep timer's last seconds (Android `ClockSleepTimer` / `ShakeListener`):
/// a short vibration and accelerometer shake detection. Both need a real device; the
/// simulator has no accelerometer or vibration motor, so these calls are no-ops there.
@MainActor
final class SleepTimerDeviceFeedback {
    private let motion = CMMotionManager()
    private var onShake: (() -> Void)?
    private var lastShake: Date?

    var isListeningForShake: Bool { onShake != nil }

    /// Android vibrates 500 ms; iOS exposes the system vibration (~0.4 s) for background apps.
    func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    /// Starts accelerometer updates (works while background audio keeps the app running).
    func startShakeDetection(_ handler: @escaping () -> Void) {
        guard onShake == nil else { return }
        onShake = handler
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 20
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            MainActor.assumeIsolated {
                guard SleepTimerLogic.isShake(x: a.x, y: a.y, z: a.z) else { return }
                // One reset per shake gesture, not per sample.
                if let last = self.lastShake, Date().timeIntervalSince(last) < 1 { return }
                self.lastShake = Date()
                self.onShake?()
            }
        }
    }

    func stopShakeDetection() {
        onShake = nil
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
    }
}
