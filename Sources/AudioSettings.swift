import Foundation
import Combine

class AudioSettings: ObservableObject {
    static let shared = AudioSettings()

    @Published var volume: Float {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            AudioEngineManager.shared.volume = effectiveVolume
        }
    }

    @Published var pitch: Float {
        didSet {
            UserDefaults.standard.set(pitch, forKey: "pitch")
            AudioEngineManager.shared.pitch = pitch
        }
    }

    @Published var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: "isMuted")
            AudioEngineManager.shared.volume = effectiveVolume
        }
    }

    /// User-selectable option: pause typing sounds when the microphone is active in a call.
    @Published var autoMuteOnMic: Bool {
        didSet {
            UserDefaults.standard.set(autoMuteOnMic, forKey: "autoMuteOnMic")
            MicMonitor.shared.setEnabled(autoMuteOnMic)
            if !autoMuteOnMic {
                isAutoMutedByMic = false
            }
        }
    }

    @Published var isAutoMutedByMic: Bool = false {
        didSet {
            AudioEngineManager.shared.volume = effectiveVolume
        }
    }

    /// 0 = off, 1 = noticeable softening during rapid typing bursts.
    @Published var velocitySensitivity: Double {
        didSet {
            UserDefaults.standard.set(velocitySensitivity, forKey: "velocitySensitivity")
            AudioEngineManager.shared.velocitySensitivity = velocitySensitivity
        }
    }

    var effectiveMuted: Bool {
        isMuted || (autoMuteOnMic && isAutoMutedByMic)
    }

    var effectiveVolume: Float {
        effectiveMuted ? 0.0 : volume
    }

    private init() {
        self.volume = UserDefaults.standard.object(forKey: "volume") as? Float ?? 1.0
        self.pitch = UserDefaults.standard.object(forKey: "pitch") as? Float ?? 1.0
        self.isMuted = UserDefaults.standard.bool(forKey: "isMuted")
        self.autoMuteOnMic = UserDefaults.standard.bool(forKey: "autoMuteOnMic")
        self.velocitySensitivity = UserDefaults.standard.object(forKey: "velocitySensitivity") as? Double ?? 0.35

        AudioEngineManager.shared.volume = effectiveVolume
        AudioEngineManager.shared.pitch = self.pitch
        AudioEngineManager.shared.velocitySensitivity = self.velocitySensitivity

        if autoMuteOnMic {
            MicMonitor.shared.setEnabled(true)
        }
    }
}
