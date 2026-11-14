import AVFoundation

// RecipeEngine v2: sample-based renderer.
// At load/update time it pre-renders per-layer, per-key-category, per-variant buffers
// (pitch / trim / lowpass baked in). At trigger time it just picks buffers — no RT work.

final class RecipeEngine {
    struct TriggerResult {
        var buffers: [AVAudioPCMBuffer]
        var volume: Float   // humanize gain jitter, applied via player.volume
        var pan: Float      // -1 left ... 1 right
    }

    private(set) var recipe: SoundRecipe?
    private var rng = SystemRandomNumberGenerator()

    /// prerendered[layerName][category] -> variants. layerName: click / body / release.
    private var prerendered: [String: [String: [AVAudioPCMBuffer]]] = [:]

    static let categories = ["generic", "space", "enter", "backspace", "modifier"]
    static let variantsPerKey = 5

    // Provided by AudioEngineManager (file IO + normalization stay there).
    var loadSample: ((SoundRecipe.SampleRef) -> AVAudioPCMBuffer?)?
    var normalizeBuffer: ((AVAudioPCMBuffer, Float) -> Void)?
    var packVolume: ((String) -> Float)?

    func load(recipe: SoundRecipe) {
        self.recipe = recipe
        prerender()
    }

    /// Live-update from the Sound Lab panel. Re-renders all variants (fast: few short samples).
    func update(recipe: SoundRecipe) {
        self.recipe = recipe
        prerender()
    }

    // MARK: - Prerender

    private func prerender() {
        guard let recipe = recipe, let loadSample = loadSample else { return }
        prerendered.removeAll()

        let layers: [(String, SoundRecipe.SampleLayer)] = [
            ("click", recipe.layers.click),
            ("body", recipe.layers.body),
            ("release", recipe.layers.release)
        ]

        for (name, layer) in layers {
            guard layer.enabled, let sample = layer.sample else { continue }
            var perCategory: [String: [AVAudioPCMBuffer]] = [:]

            for category in RecipeEngine.categories {
                let kv = recipe.keymap.override(for: category) ?? SoundRecipe.KeyOverride()
                let targetGain = Float(layer.gain * kv.gainScale * recipe.master.gain)
                    * (packVolume?(sample.pack) ?? 1.0)

                var variants: [AVAudioPCMBuffer] = []
                for _ in 0..<RecipeEngine.variantsPerKey {
                    guard var buffer = loadSample(sample) else { break }

                    // Pitch: base shift + category override + humanize jitter
                    let jitter = Double.random(in: -recipe.humanize.pitchJitterSt...recipe.humanize.pitchJitterSt, using: &rng)
                    let semis = layer.pitchShiftSt + kv.pitchShift + jitter
                    buffer = RecipeEngine.resample(buffer, semitones: semis) ?? buffer

                    if layer.trimMs > 0 { RecipeEngine.trim(buffer, ms: layer.trimMs) }
                    if layer.lowpassHz < 20000 { RecipeEngine.lowpass(buffer, cutoffHz: layer.lowpassHz) }
                    normalizeBuffer?(buffer, targetGain)
                    variants.append(buffer)
                }
                if !variants.isEmpty { perCategory[category] = variants }
            }
            prerendered[name] = perCategory
        }
    }

    // MARK: - Triggers

    func triggerDown(keyCode: Int64) -> TriggerResult {
        guard let recipe = recipe else { return TriggerResult(buffers: [], volume: 1, pan: 0) }
        let cat = RecipeEngine.category(for: keyCode)
        var buffers: [AVAudioPCMBuffer] = []
        for name in ["click", "body"] {
            if let buffer = pick(layer: name, category: cat) {
                buffers.append(buffer)
            }
        }
        return TriggerResult(buffers: buffers, volume: gainJitter(recipe), pan: pan(for: keyCode, recipe: recipe))
    }

    func triggerUp(keyCode: Int64) -> TriggerResult? {
        guard let recipe = recipe, recipe.layers.release.enabled else { return nil }
        let cat = RecipeEngine.category(for: keyCode)
        guard let buffer = pick(layer: "release", category: cat) else { return nil }
        return TriggerResult(buffers: [buffer], volume: gainJitter(recipe), pan: pan(for: keyCode, recipe: recipe))
    }

    private func pick(layer: String, category: String) -> AVAudioPCMBuffer? {
        let perCat = prerendered[layer]
        let list = perCat?[category] ?? perCat?["generic"]
        return list?.randomElement(using: &rng)
    }

    private func gainJitter(_ recipe: SoundRecipe) -> Float {
        let db = Double.random(in: -recipe.humanize.gainJitterDb...recipe.humanize.gainJitterDb, using: &rng)
        return Float(pow(10.0, db / 20.0))
    }

    private func pan(for keyCode: Int64, recipe: SoundRecipe) -> Float {
        let col = RecipeEngine.keyPositions[keyCode]?.col ?? 7
        let norm = Float(col) / 13.0 * 2 - 1
        return norm * Float(recipe.layers.space.stereoWidth)
    }

    // MARK: - Key mapping

    static func category(for keyCode: Int64) -> String {
        switch keyCode {
        case 36: return "enter"
        case 49: return "space"
        case 51: return "backspace"
        case 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: return "modifier"
        default: return "generic"
        }
    }

    // ANSI-ish key position map: keyCode -> (row, column), row 0 = number row.
    static let keyPositions: [Int64: (row: Int, col: Int)] = [
        50: (0, 0), 18: (0, 1), 19: (0, 2), 20: (0, 3), 21: (0, 4), 23: (0, 5),
        22: (0, 6), 26: (0, 7), 28: (0, 8), 25: (0, 9), 29: (0, 10), 27: (0, 11),
        24: (0, 12), 51: (0, 13),
        48: (1, 0), 12: (1, 1), 13: (1, 2), 14: (1, 3), 15: (1, 4), 17: (1, 5),
        16: (1, 6), 32: (1, 7), 34: (1, 8), 31: (1, 9), 35: (1, 10), 33: (1, 11),
        30: (1, 12), 36: (1, 13),
        57: (2, 0), 0: (2, 1), 1: (2, 2), 2: (2, 3), 3: (2, 4), 5: (2, 5),
        4: (2, 6), 38: (2, 7), 37: (2, 8), 40: (2, 9), 41: (2, 10), 39: (2, 11),
        42: (2, 12),
        56: (3, 0), 6: (3, 1), 7: (3, 2), 8: (3, 3), 9: (3, 4), 11: (3, 5),
        45: (3, 6), 46: (3, 7), 43: (3, 8), 47: (3, 9), 44: (3, 10), 61: (3, 12),
        53: (4, 0), 55: (4, 1), 58: (4, 2), 59: (4, 3), 49: (4, 6),
        54: (4, 11), 60: (4, 12), 62: (4, 13), 63: (4, 10)
    ]

    // MARK: - Offline buffer processing (called at prerender time, never on RT thread)

    /// Varispeed-style pitch shift (changes duration too) via linear resampling.
    static func resample(_ src: AVAudioPCMBuffer, semitones: Double) -> AVAudioPCMBuffer? {
        let ratio = pow(2.0, semitones / 12.0)
        guard abs(ratio - 1) > 0.005, let srcData = src.floatChannelData else { return nil }

        let format = src.format
        let inFrames = Int(src.frameLength)
        let outFrames = max(1, Int(Double(inFrames) / ratio))
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(outFrames)),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(outFrames)

        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            let srcCh = srcData[ch]
            let outCh = outData[ch]
            for i in 0..<outFrames {
                let pos = Double(i) * ratio
                let i0 = Int(pos)
                let i1 = min(i0 + 1, inFrames - 1)
                let frac = Float(pos - Double(i0))
                outCh[i] = srcCh[i0] * (1 - frac) + srcCh[i1] * frac
            }
        }
        return out
    }

    /// Hard-trim the buffer to the given duration (start is kept; the attack lives there).
    static func trim(_ buffer: AVAudioPCMBuffer, ms: Double) {
        let frames = AVAudioFrameCount(ms / 1000.0 * buffer.format.sampleRate)
        if frames > 0 && frames < buffer.frameLength {
            buffer.frameLength = frames
        }
    }

    /// One-pole lowpass, in place. Gives the "foam / tape mod" damping.
    static func lowpass(_ buffer: AVAudioPCMBuffer, cutoffHz: Double) {
        guard let data = buffer.floatChannelData else { return }
        let dt = 1.0 / buffer.format.sampleRate
        let rc = 1.0 / (2 * .pi * cutoffHz)
        let a = Float(dt / (rc + dt))
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for ch in 0..<channels {
            let d = data[ch]
            var y: Float = 0
            for i in 0..<frames {
                y += a * (d[i] - y)
                d[i] = y
            }
        }
    }
}
