import AVFoundation

/// Small utility to toggle the device torch (flashlight).
/// Safe on devices without a torch and when the camera is in use (ARKit).
final class TorchService {
    static let shared = TorchService()
    private init() {}

    /// Turn the torch on/off.
    /// - Parameters:
    ///   - enabled: Desired torch state.
    ///   - level: Torch brightness 0.0...1.0 (iOS clamps to supported range).
    func setTorch(enabled: Bool, level: Float = 1.0) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if enabled {
                let clamped = max(0.01, min(level, 1.0))
                try device.setTorchModeOn(level: clamped)
            } else {
                device.torchMode = .off
            }
        } catch {
            #if DEBUG
            print("ERROR: TorchService failed to set torch: \(error)")
            #endif
        }
    }
}
