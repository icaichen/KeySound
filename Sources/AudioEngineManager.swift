import AVFoundation
import Accelerate

class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()
    
    private var engine: AVAudioEngine
    private var speedUnit: AVAudioUnitVarispeed
    private var playersMixer: AVAudioMixerNode // Sub-mixer for players before Varispeed
    private var mainMixer: AVAudioMixerNode
    
    // Serial queue for audio triggering to prevent blocking the main thread (Event Tap)
    private let audioQueue = DispatchQueue(label: "com.keysound.audio", qos: .userInteractive)
    
    // Pool of players to handle polyphony
    private var players: [AVAudioPlayerNode] = []
    private let poolSize = 32 // Increased for better polyphony
    private var currentPlayerIndex = 0
    
    // Sound Buffers: [Filename: Buffer]
    // Special keys are mapped: "enter" -> [Buffer], "space" -> [Buffer]
    private var soundBuffers: [String: [AVAudioPCMBuffer]] = [:]
    private var specialSoundBuffers: [String: [AVAudioPCMBuffer]] = [:]
    
    // Per-profile volume adjustments to balance loudness
    private let profileVolumeSettings: [String: Float] = [
        "MX_Blue": 0.5,
        "MX_Brown": 0.7,
        "MX_Black": 0.8,
        "Mahjong": 1.0,
        "Thocky": 0.9,
        "Creamy": 0.9,
        "iPhone": 0.4,
        "BlackBerry": 0.7,
        "Opera_GX": 0.7
    ]
    
    // Settings
    var volume: Float = 1.0 {
        didSet {
            updateVolume()
        }
    }
    
    var pitch: Float = 1.0 {
        didSet {
            updatePitch()
        }
    }
    
    private init() {
        engine = AVAudioEngine()
        speedUnit = AVAudioUnitVarispeed()
        playersMixer = AVAudioMixerNode()
        mainMixer = engine.mainMixerNode
        
        // Attach nodes
        engine.attach(speedUnit)
        engine.attach(playersMixer)
        
        let format = mainMixer.outputFormat(forBus: 0)
        
        // Connect PlayersMixer -> SpeedUnit -> MainMixer
        // Note: Varispeed is 1-in-1-out, so we mix all players into playersMixer first.
        engine.connect(playersMixer, to: speedUnit, format: format)
        engine.connect(speedUnit, to: mainMixer, format: format)
        
        // Create pool
        for _ in 0..<poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            players.append(player)
            // Connect player -> playersMixer
            engine.connect(player, to: playersMixer, format: format)
        }
        
        // Start engine
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
        
        // Load initial settings
        self.volume = UserDefaults.standard.float(forKey: "volume")
        if self.volume == 0 { self.volume = 1.0 }
        self.pitch = UserDefaults.standard.float(forKey: "pitch")
        if self.pitch == 0 { self.pitch = 1.0 }
        
        updateVolume()
        updatePitch()
    }
    
    func updateVolume() {
        // Apply volume to main mixer (0.0 - 1.0)
        // If user wants BOOST (>1.0), we can't do it here easily without distortion or EQ.
        // For now, map 0.0-1.0 to 0.0-1.0. 
        // We will implement normalization in buffer loading to ensure max volume.
        mainMixer.outputVolume = volume
    }
    
    func updatePitch() {
        // AVAudioUnitVarispeed rate: 1.0 is normal. 
        // 2.0 is 1 octave up (2x speed).
        // 0.5 is 1 octave down (0.5x speed).
        speedUnit.rate = pitch
    }
    
    func loadSounds(for profile: String) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.soundBuffers.removeAll()
            self.specialSoundBuffers.removeAll()
            
            var soundsURL: URL?
            
            // 1. Try standard App Bundle Resources
            if let resourceURL = Bundle.main.resourceURL {
                let candidate = resourceURL.appendingPathComponent("Sounds").appendingPathComponent(profile)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir) && isDir.boolValue {
                    soundsURL = candidate
                }
            }
            
            // 2. Fallback to SPM Module
            if soundsURL == nil {
                soundsURL = Bundle.module.resourceURL?.appendingPathComponent("Sounds").appendingPathComponent(profile)
            }
            
            guard let finalURL = soundsURL else {
                return
            }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: finalURL.path)
                let wavs = files.filter { $0.hasSuffix(".wav") }.sorted()
                
                let targetVolume = self.profileVolumeSettings[profile] ?? 1.0
                
                for file in wavs {
                    let url = finalURL.appendingPathComponent(file)
                    if let buffer = self.loadBuffer(url: url) {
                        let lowerFile = file.lowercased()
                        
                        // Normalize buffer to maximize volume
                        self.normalize(buffer: buffer, targetVolume: targetVolume)
                        
                        if lowerFile.contains("enter") || lowerFile.contains("return") {
                            self.addSpecial(key: "enter", buffer: buffer)
                        } else if lowerFile.contains("space") {
                            self.addSpecial(key: "space", buffer: buffer)
                        } else if lowerFile.contains("back") || lowerFile.contains("delete") {
                            self.addSpecial(key: "backspace", buffer: buffer)
                        } else if lowerFile.contains("modifier") || lowerFile.contains("shift") || lowerFile.contains("ctrl") || lowerFile.contains("alt") || lowerFile.contains("cmd") {
                            self.addSpecial(key: "modifier", buffer: buffer)
                        } else {
                            // Generic
                            var list = self.soundBuffers["generic"] ?? []
                            list.append(buffer)
                            self.soundBuffers["generic"] = list
                        }
                    }
                }
            } catch {
                print("Error loading sounds for \(profile): \(error)")
            }
        }
    }
    
    private func loadBuffer(url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            let processingFormat = file.processingFormat
            let standardFormat = mainMixer.outputFormat(forBus: 0) // Convert to mixer format
            
            // Read file into processing format buffer
            guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: fileBuffer)
            
            // Convert to standard format
            guard let converter = AVAudioConverter(from: processingFormat, to: standardFormat) else { return nil }
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: standardFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil } // Approx length
            
            var error: NSError? = nil
            converter.convert(to: convertedBuffer, error: &error) { packetCount, outStatus in
                outStatus.pointee = .haveData
                return fileBuffer
            }
            
            if let error = error {
                print("Error converting buffer: \(error)")
                return nil
            }
            
            return convertedBuffer
        } catch {
            print("Error reading audio file \(url): \(error)")
            return nil
        }
    }
    
    private func normalize(buffer: AVAudioPCMBuffer, targetVolume: Float = 1.0) {
        // Simple normalization: Find max amplitude and scale to targetVolume (default 1.0)
        // Or apply a fixed boost if needed.
        // Using vDSP for performance if possible, or simple loop.
        
        guard let floatData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var maxAmp: Float = 0.0
        
        // Find max
        for channel in 0..<channelCount {
            let channelData = floatData[channel]
            var channelMax: Float = 0.0
            vDSP_maxmgv(channelData, 1, &channelMax, vDSP_Length(frameLength))
            if channelMax > maxAmp {
                maxAmp = channelMax
            }
        }
        
        // Scale
        if maxAmp > 0.0001 { // Avoid div by zero
            // Target amplitude: targetVolume (scaled relative to 1.0 peak)
            let scale = targetVolume / maxAmp
            // Apply gain
             for channel in 0..<channelCount {
                let channelData = floatData[channel]
                var gain = scale
                vDSP_vsmul(channelData, 1, &gain, channelData, 1, vDSP_Length(frameLength))
            }
        }
    }
    
    private func addSpecial(key: String, buffer: AVAudioPCMBuffer) {
        var list = specialSoundBuffers[key] ?? []
        list.append(buffer)
        specialSoundBuffers[key] = list
    }
    
    func playSound(for keyCode: Int64) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            var buffers: [AVAudioPCMBuffer]?
            
            switch keyCode {
            case 36: // Return
                buffers = self.specialSoundBuffers["enter"]
            case 49: // Space
                buffers = self.specialSoundBuffers["space"]
            case 51: // Delete
                buffers = self.specialSoundBuffers["backspace"]
            case 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: // Modifiers
                buffers = self.specialSoundBuffers["modifier"]
            default:
                break
            }
            
            if buffers == nil || buffers!.isEmpty {
                buffers = self.soundBuffers["generic"]
            }
            
            guard let candidates = buffers, !candidates.isEmpty else { return }
            
            // Random pick for generic
            let buffer = candidates.randomElement()!
            
            // Play
            self.playBuffer(buffer)
        }
    }
    
    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        // Ensure engine is running (lightweight check)
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Error restarting engine: \(error)")
                return
            }
        }
        
        let player = players[currentPlayerIndex]
        currentPlayerIndex = (currentPlayerIndex + 1) % poolSize
        
        // Schedule buffer
        // .interrupts options is not available on scheduleBuffer? 
        // Actually scheduleBuffer appends. 
        // If we want to cut off previous sound on this specific player (unlikely with pool of 32),
        // we would stop it. But stop() clears the queue.
        // With 32 players, overlap is fine.
        
        if player.isPlaying {
            player.stop() // Clear previous buffer if any (unlikely to happen often with 32 players)
        }
        
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }
}
