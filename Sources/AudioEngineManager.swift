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
    
    // Recipe mode ("Sound Lab" profile): sample-based DJ board renderer
    static let recipeProfileName = "Sound Lab"
    private var recipeEngine: RecipeEngine?
    private var isRecipeProfile = false
    private var recipeEQ: AVAudioUnitEQ?
    private var recipeReverb: AVAudioUnitReverb?
    
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
        "Opera_GX": 0.7,
        "ALPS": 0.8
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

    /// 0 = constant volume, 1 = noticeable softening during rapid typing bursts.
    var velocitySensitivity: Double = 0.35
    private var lastKeyDownTime: CFAbsoluteTime = 0
    
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
            
            // Recipe mode: Sound Lab workspace or a named Saved Mix
            if profile == AudioEngineManager.recipeProfileName {
                self.setupRecipeMode()
                return
            }
            if profile.hasPrefix(SoundPackCatalog.savedRecipePrefix) {
                let base = String(profile.dropFirst(SoundPackCatalog.savedRecipePrefix.count))
                let url = SoundPackCatalog.savedRecipesDirectory().appendingPathComponent("\(base).recipe.json")
                if let loaded = try? SoundRecipe.load(from: url) {
                    if self.isRecipeProfile {
                        self.teardownRecipeMode()
                    }
                    self.setupRecipeMode(overrideRecipe: loaded)
                    return
                }
            }
            self.teardownRecipeMode()
            
            var soundsURL: URL?
            
            // 1. Try standard App Bundle Resources
            if let resourceURL = Bundle.main.resourceURL {
                let candidate = resourceURL.appendingPathComponent("Sounds").appendingPathComponent(profile)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir) && isDir.boolValue {
                    soundsURL = candidate
                }
            }
            
            // 2. Fallback to user / AI-generated custom packs
            if soundsURL == nil {
                let candidate = SoundPackCatalog.customPacksDirectory().appendingPathComponent(profile)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    soundsURL = candidate
                }
            }

            // 3. Fallback to SPM Module (debug `swift run` only)
            if soundsURL == nil {
                let candidate = SoundPackCatalog.safeModuleResourceURL?.appendingPathComponent("Sounds").appendingPathComponent(profile)
                var isDir: ObjCBool = false
                if let c = candidate, FileManager.default.fileExists(atPath: c.path, isDirectory: &isDir), isDir.boolValue {
                    soundsURL = c
                }
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
    
    // MARK: - Recipe mode (Sound Lab)
    
    /// Where the Sound Lab panel saves the user's tuned recipe.
    static var userRecipeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeySound/Recipes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom-thock.recipe.json")
    }
    
    /// Current recipe on the engine (nil when a sample profile is active).
    var currentRecipe: SoundRecipe? { recipeEngine?.recipe }
    
    /// Live-update recipe params from the Sound Lab panel.
    func updateRecipe(_ recipe: SoundRecipe) {
        audioQueue.async { [weak self] in
            guard let self = self, self.isRecipeProfile else { return }
            let hadReverb = self.recipeReverb != nil
            self.recipeEngine?.update(recipe: recipe)
            // Space layer toggled -> rebuild the chain; otherwise update node params in place
            if recipe.layers.space.enabled != hadReverb {
                self.applyRecipeChainAfterTear()
            } else {
                if let eq = self.recipeEQ { self.configureRecipeEQ(eq, recipe: recipe) }
                if let reverb = self.recipeReverb { self.configureRecipeReverb(reverb, recipe: recipe) }
            }
        }
    }
    
    /// Rebuild EQ/reverb chain (reverb node added or removed).
    private func applyRecipeChainAfterTear() {
        guard let recipe = recipeEngine?.recipe else { return }
        if let eq = recipeEQ { engine.detach(eq) }
        if let reverb = recipeReverb { engine.detach(reverb) }
        recipeEQ = nil
        recipeReverb = nil
        applyRecipeChain(recipe)
    }
    
    /// Persist the user's recipe so it survives restarts and is preferred over the bundle preset.
    func saveRecipe(_ recipe: SoundRecipe) {
        let url = AudioEngineManager.userRecipeURL
        do {
            let data = try JSONEncoder().encode(recipe)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Sound Lab: failed to save recipe: \(error)")
        }
    }
    
    /// Save a named mix to `SavedRecipes/` so it appears in Sound Library and never overwrites built-in presets.
    @discardableResult
    func saveNamedRecipe(_ recipe: SoundRecipe) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(recipe.meta.name.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let base = cleaned.isEmpty ? "custom-mix-\(Int(Date().timeIntervalSince1970))" : cleaned
        let url = SoundPackCatalog.savedRecipesDirectory().appendingPathComponent("\(base).recipe.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recipe)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Sound Lab: failed to save named recipe: \(error)")
        }
        saveRecipe(recipe)
        return "\(SoundPackCatalog.savedRecipePrefix)\(base)"
    }

    /// Delete the user's saved recipe (Sound Lab "Reset").
    func deleteUserRecipe() {
        try? FileManager.default.removeItem(at: AudioEngineManager.userRecipeURL)
    }
    
    /// All bundled preset files (Recipes/presets/*.recipe.json), sorted by filename.
    /// Same lookup order as bundledRecipe(): app bundle first, SPM module as fallback.
    func bundledPresetURLs() -> [URL] {
        var dir: URL?
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Recipes/presets")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                dir = candidate
            }
        }
        if dir == nil {
            dir = SoundPackCatalog.safeModuleResourceURL?.appendingPathComponent("Recipes/presets")
        }
        guard let finalDir = dir else { return [] }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: finalDir.path)) ?? [])
            .filter { $0.hasSuffix(".recipe.json") }
            .sorted()
        return files.map { finalDir.appendingPathComponent($0) }
    }

    /// Load a preset file for auditioning. Does not touch the user's saved recipe
    /// (that only happens via saveRecipe / deleteUserRecipe).
    func loadPresetFile(_ url: URL) -> SoundRecipe? {
        try? SoundRecipe.load(from: url)
    }

    /// Load the bundled custom-thock preset, ignoring the user's saved recipe.
    func bundledRecipe() -> SoundRecipe? {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Recipes/presets/custom-thock.recipe.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? SoundRecipe.load(from: candidate)
            }
        }
        // SPM debug builds only; never reached in a packaged .app
        if let candidate = SoundPackCatalog.safeModuleResourceURL?.appendingPathComponent("Recipes/presets/custom-thock.recipe.json"),
           FileManager.default.fileExists(atPath: candidate.path) {
            return try? SoundRecipe.load(from: candidate)
        }
        return nil
    }
    
    /// Must be called on audioQueue. Builds the recipe renderer and inserts EQ/reverb into the chain.
    private func setupRecipeMode(overrideRecipe: SoundRecipe? = nil) {
        guard !isRecipeProfile else { return }
        
        // Search order: explicit saved mix -> user's workspace recipe -> app bundle -> SPM module bundle.
        var recipe: SoundRecipe? = overrideRecipe
        if recipe == nil {
            let userURL = AudioEngineManager.userRecipeURL
            if FileManager.default.fileExists(atPath: userURL.path) {
                recipe = try? SoundRecipe.load(from: userURL)
            }
        }
        if recipe == nil {
            recipe = bundledRecipe()
        }
        guard let recipe = recipe else {
            print("Sound Lab: failed to load recipe")
            return
        }
        
        let re = RecipeEngine()
        re.loadSample = { [weak self] ref in self?.loadSampleBuffer(ref: ref) }
        re.normalizeBuffer = { [weak self] buffer, target in self?.normalize(buffer: buffer, targetVolume: target) }
        re.packVolume = { [weak self] pack in self?.profileVolumeSettings[pack] ?? 1.0 }
        re.load(recipe: recipe)
        recipeEngine = re
        isRecipeProfile = true
        applyRecipeChain(recipe)
    }
    
    /// Insert playersMixer -> EQ -> [reverb] -> speedUnit for recipe mode.
    private func applyRecipeChain(_ recipe: SoundRecipe) {
        let format = mainMixer.outputFormat(forBus: 0)
        engine.disconnectNodeOutput(playersMixer)
        
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        configureRecipeEQ(eq, recipe: recipe)
        engine.attach(eq)
        engine.connect(playersMixer, to: eq, format: format)
        recipeEQ = eq
        
        var tail: AVAudioNode = eq
        if recipe.layers.space.enabled {
            let reverb = AVAudioUnitReverb()
            configureRecipeReverb(reverb, recipe: recipe)
            engine.attach(reverb)
            engine.connect(eq, to: reverb, format: format)
            recipeReverb = reverb
            tail = reverb
        }
        engine.connect(tail, to: speedUnit, format: format)
    }
    
    private func configureRecipeEQ(_ eq: AVAudioUnitEQ, recipe: SoundRecipe) {
        let e = recipe.master.eq
        let bands = eq.bands
        bands[0].filterType = .lowShelf
        bands[0].frequency = 250
        bands[0].gain = Float(e.lowDb)
        bands[0].bypass = e.lowDb == 0
        bands[1].filterType = .parametric
        bands[1].frequency = 1000
        bands[1].bandwidth = 1.0
        bands[1].gain = Float(e.midDb)
        bands[1].bypass = e.midDb == 0
        bands[2].filterType = .highShelf
        bands[2].frequency = 6000
        bands[2].gain = Float(e.highDb)
        bands[2].bypass = e.highDb == 0
        eq.globalGain = 0
    }
    
    private func configureRecipeReverb(_ reverb: AVAudioUnitReverb, recipe: SoundRecipe) {
        let s = recipe.layers.space
        let preset: AVAudioUnitReverbPreset = s.roomSize < 0.33 ? .smallRoom
            : s.roomSize < 0.66 ? .mediumRoom : .largeHall
        reverb.loadFactoryPreset(preset)
        reverb.wetDryMix = Float(s.reverbWet * 100)
    }
    
    /// Must be called on audioQueue.
    private func teardownRecipeMode() {
        guard isRecipeProfile else { return }
        if let eq = recipeEQ { engine.detach(eq) }
        if let reverb = recipeReverb { engine.detach(reverb) }
        recipeEQ = nil
        recipeReverb = nil
        // Restore the direct playersMixer -> speedUnit connection
        let format = mainMixer.outputFormat(forBus: 0)
        engine.disconnectNodeOutput(playersMixer)
        engine.connect(playersMixer, to: speedUnit, format: format)
        recipeEngine = nil
        isRecipeProfile = false
    }
    
    /// Play a raw sample once (Sound Lab picker preview).
    func previewSample(_ ref: SoundRecipe.SampleRef) {
        audioQueue.async { [weak self] in
            guard let self = self, let buffer = self.loadSampleBuffer(ref: ref) else { return }
            self.playBuffer(buffer)
        }
    }
    
    /// Resolve a recipe sample reference into a converted buffer.
    /// file == "generic" means: pick one of the pack's generic variants (1.wav-5.wav) at random.
    private func loadSampleBuffer(ref: SoundRecipe.SampleRef) -> AVAudioPCMBuffer? {
        var url: URL?
        if ref.pack == "@user" {
            url = URL(fileURLWithPath: ref.file)
        } else {
            let fileName = ref.file == "generic" ? "\(Int.random(in: 1...5)).wav" : ref.file
            if let resourceURL = Bundle.main.resourceURL {
                let candidate = resourceURL.appendingPathComponent("Sounds/\(ref.pack)/\(fileName)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    url = candidate
                }
            }
            if url == nil, let moduleURL = SoundPackCatalog.safeModuleResourceURL {
                let candidate = moduleURL.appendingPathComponent("Sounds/\(ref.pack)/\(fileName)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    url = candidate
                }
            }
        }
        guard let finalURL = url else { return nil }
        return loadBuffer(url: finalURL)
    }
    
    /// All samples in all built-in packs, for the Sound Lab pickers.
    func sampleCatalog() -> [(pack: String, files: [String])] {
        var soundsURL: URL?
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Sounds")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                soundsURL = candidate
            }
        }
        if soundsURL == nil {
            soundsURL = SoundPackCatalog.safeModuleResourceURL?.appendingPathComponent("Sounds")
        }
        guard let finalURL = soundsURL else { return [] }
        
        let packs = (try? FileManager.default.contentsOfDirectory(atPath: finalURL.path)) ?? []
        var catalog: [(String, [String])] = []
        for pack in packs where !pack.hasPrefix(".") {
            var isDir: ObjCBool = false
            let packURL = finalURL.appendingPathComponent(pack)
            guard FileManager.default.fileExists(atPath: packURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: packURL.path)) ?? [])
                .filter { $0.hasSuffix(".wav") }
                .sorted()
            if !files.isEmpty { catalog.append((pack, files)) }
        }
        return catalog.sorted { $0.0 < $1.0 }
    }
    
    func playRelease(for keyCode: Int64) {
        guard isRecipeProfile else { return }
        audioQueue.async { [weak self] in
            guard let self = self, let result = self.recipeEngine?.triggerUp(keyCode: keyCode) else { return }
            for buffer in result.buffers {
                self.playBuffer(buffer, volume: result.volume, pan: result.pan)
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
    
    private func velocityScale() -> Float {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - lastKeyDownTime
        lastKeyDownTime = now
        guard velocitySensitivity > 0.01, dt > 0, dt < 0.16 else { return 1.0 }
        // Fast typing (< 160ms between keys) gently softens each hit so bursts feel organic.
        let t = max(0.0, min(1.0, (0.16 - dt) / 0.12))
        return Float(1.0 - t * 0.28 * velocitySensitivity)
    }

    func playSound(for keyCode: Int64) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let vScale = self.velocityScale()
            
            // Recipe mode: layered sample playback
            if self.isRecipeProfile {
                if let result = self.recipeEngine?.triggerDown(keyCode: keyCode) {
                    for buffer in result.buffers {
                        self.playBuffer(buffer, volume: result.volume * vScale, pan: result.pan)
                    }
                }
                return
            }
            
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
            self.playBuffer(buffer, volume: vScale)
        }
    }
    
    private func playBuffer(_ buffer: AVAudioPCMBuffer, volume: Float = 1.0, pan: Float = 0.0) {
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
        
        if player.isPlaying {
            player.stop() // Clear previous buffer if any (unlikely to happen often with 32 players)
        }
        
        player.volume = volume
        player.pan = pan
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }
}
