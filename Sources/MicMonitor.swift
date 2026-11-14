import Foundation
import CoreAudio

/// Lightweight opt-in monitor that checks whether any app is actively using
/// the default audio input device (e.g. Zoom, Meet, Slack, Discord).
final class MicMonitor {
    static let shared = MicMonitor()

    private var timer: Timer?
    var onMicStateChanged: ((Bool) -> Void)?

    private init() {}

    func setEnabled(_ enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = nil
            if enabled {
                self.checkMic()
                self.timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.checkMic()
                }
            }
        }
    }

    private func checkMic() {
        let active = Self.isDefaultInputRunning()
        if AudioSettings.shared.isAutoMutedByMic != active {
            AudioSettings.shared.isAutoMutedByMic = active
            onMicStateChanged?(active)
        }
    }

    private static func isDefaultInputRunning() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return false }

        var isRunning: UInt32 = 0
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let runStatus = AudioObjectGetPropertyData(deviceID, &runAddress, 0, nil, &runSize, &isRunning)
        return runStatus == noErr && isRunning != 0
    }
}
