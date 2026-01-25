import Foundation
import Combine

class AudioSettings: ObservableObject {
    static let shared = AudioSettings()
    
    @Published var volume: Float {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            AudioEngineManager.shared.volume = volume
        }
    }
    
    @Published var pitch: Float {
        didSet {
            UserDefaults.standard.set(pitch, forKey: "pitch")
            AudioEngineManager.shared.pitch = pitch
        }
    }
    
    private init() {
        self.volume = UserDefaults.standard.object(forKey: "volume") as? Float ?? 1.0
        self.pitch = UserDefaults.standard.object(forKey: "pitch") as? Float ?? 1.0
        // Sync initial values
        AudioEngineManager.shared.volume = self.volume
        AudioEngineManager.shared.pitch = self.pitch
    }
}
